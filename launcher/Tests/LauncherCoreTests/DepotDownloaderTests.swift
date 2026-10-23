import CryptoKit
import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fixtures

private let session = SteamSession(accountName: "joao", steamID: 1, refreshToken: "refresh-jwt", accessToken: "a")
private let depots = [
    Depot(id: 331161, oslist: [], osarch: nil, publicManifest: 11, maxSize: 3_000),
    Depot(id: 331162, oslist: ["windows"], osarch: nil, publicManifest: 12, maxSize: 1_000, language: "english"),
]

/// A fake DepotDownloader. What it does comes from `<dir>/mode`; it records its arguments in `<dir>/args`
/// and a copy of the account store as it found it in `<dir>/seen.config`.
private func makeFakeBinary(in dir: URL, store: URL, isolatedRoot: URL) throws -> URL {
    let binary = dir.appendingPathComponent("DepotDownloader")
    let script = """
        #!/bin/sh
        here="$(cd "$(dirname "$0")" && pwd)"
        if [ "$1" = "-V" ]; then mkdir -p "\(isolatedRoot.path)/r1/r2/Url.fake/AssemFiles"; echo "3.4.0"; exit 0; fi
        printf '%s\\n' "$@" > "$here/args"
        cp "\(store.path)" "$here/seen.config" 2>/dev/null
        case "$(cat "$here/mode")" in
          ok)
            echo "Processing depot 331161"
            echo "Downloading depot 331161 manifest"
            echo "Processing depot 331162"
            echo "Downloading depot 331162 manifest"
            echo "Downloading depot 331161"
            printf '\\033]9;4;1;10\\007 50.00%% /g/a.dat\\n'
            echo "100.00% /g/b.dat"
            echo "Downloading depot 331162"
            echo " 50.00% /g/c.dat"
            echo "100.00% /g/d.dat"
            echo "Depot 331161 - Downloaded 3000 bytes (3000 bytes uncompressed)"
            echo "Depot 331162 - Downloaded 1000 bytes (1000 bytes uncompressed)"
            echo "Total downloaded: 4000 bytes"
            exit 0 ;;
          partial)
            echo "Argument #7 -depot was not used."
            echo "Processing depot 331161"
            echo "Depot 331161 - Downloaded 3000 bytes (3000 bytes uncompressed)"
            echo "Total downloaded: 3000 bytes (3000 bytes uncompressed) from 1 depots"
            exit 0 ;;
          auth)
            echo "Access token was rejected (InvalidPassword)."
            echo "Unable to get steam3 credentials."
            echo "Error: InitializeSteam failed"
            exit 1 ;;
          fail) echo "something broke"; exit 1 ;;
          offline)
            echo "Could not connect to Steam after 10 tries"
            echo "Unable to get steam3 credentials."
            echo "Error: InitializeSteam failed"
            exit 1 ;;
          slow)
            echo "start $(date +%s%N)" >> "$here/runs"
            /bin/sleep 0.4
            echo "end $(date +%s%N)" >> "$here/runs"
            echo "Depot 331161 - Downloaded 1 bytes"
            echo "Depot 331162 - Downloaded 1 bytes"
            exit 0 ;;
          sleep) exec /bin/sleep 30 ;;
        esac

        """
    try Data(script.utf8).write(to: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    return binary
}

private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.withLock { values.append(value) } }
    var all: [Double] { lock.withLock { values } }
}

private struct Fixture {
    let dir: URL
    let store: DepotDownloaderAccountStore
    let downloader: DepotDownloader

    init(in dir: URL, mode: String) throws {
        self.dir = dir
        store = DepotDownloaderAccountStore(file: dir.appendingPathComponent("iso/AssemFiles/account.config"))
        let binary = try makeFakeBinary(in: dir, store: store.file, isolatedRoot: dir.appendingPathComponent("iso"))
        try Data(mode.utf8).write(to: dir.appendingPathComponent("mode"))
        downloader = DepotDownloader(binary: binary, accountStore: store, log: dir.appendingPathComponent("logs/dd.log"))
    }

    var args: [String] {
        ((try? String(contentsOf: dir.appendingPathComponent("args"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }
}

// MARK: - Tests

@Suite("DepotDownloader")
struct DepotDownloaderTests {
    @Test func progressAcrossDepots() {
        var parser = DepotProgress(depots: depots)
        // DepotDownloader 3.4.0 first fetches every manifest, then downloads depot by depot.
        for line in ["Processing depot 331161", "Downloading depot 331161 manifest",
                     "Processing depot 331162", "Downloading depot 331162 manifest"] {
            #expect(parser.consume(line) == nil)
        }
        // The first depot is 3/4 of the bytes, the second 1/4.
        #expect(parser.consume("Downloading depot 331161") == nil)
        #expect(parser.consume("\u{1B}]9;4;1;10\u{07} 50.00% /g/a.dat") == 0.375)
        #expect(parser.consume("100.00% /g/b.dat") == 0.75)
        #expect(parser.consume("Downloading depot 331162") == nil)
        #expect(parser.consume(" 50.00% /g/c.dat") == 0.875)
        #expect(parser.consume("100.00% /g/d.dat") == 1)
        #expect(parser.consume("Total downloaded: 4000 bytes") == nil)
    }

    @Test func progressNeverGoesBack() {
        var parser = DepotProgress(depots: depots)
        _ = parser.consume("Downloading depot 331161")
        _ = parser.consume(" 80.00% /g/a.dat")
        // Validation of an existing file can report a lower figure; the bar does not move back.
        #expect(parser.consume(" 10.00% /g/b.dat") == nil)
    }

    @Test func downloadsWithTheQRToken() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try Fixture(in: dir, mode: "ok")
            let progress = Progress()
            let target = dir.appendingPathComponent("Games/331160")

            try await fixture.downloader.download(
                appID: 331160, depots: depots, into: target, session: session) { progress.add($0) }

            // 3.4.0 takes one -depot with every id and one -manifest with every id, in the same order
            // (a repeated -depot is ignored: "Argument #7 -depot was not used.").
            #expect(fixture.args == [
                "-app", "331160", "-depot", "331161", "331162", "-manifest", "11", "12",
                "-os", "windows", "-dir", target.path, "-username", "joao", "-remember-password",
            ])
            // The token was in DepotDownloader's store before it started (ADR 0004).
            let seen = try Data(contentsOf: dir.appendingPathComponent("seen.config"))
            #expect(try AccountConfig.loginTokens(in: seen) == ["joao": "refresh-jwt"])
            #expect(progress.all == [0.375, 0.75, 0.875, 1])
            let log = try String(contentsOf: dir.appendingPathComponent("logs/dd.log"), encoding: .utf8)
            #expect(log.contains("Total downloaded"))
            #expect(!log.contains("refresh-jwt"))
        }
    }

    @Test func rejectedTokenAsksForLogin() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try Fixture(in: dir, mode: "auth")
            await #expect(throws: SteamAuthError.notLoggedIn) {
                try await fixture.downloader.download(
                    appID: 331160, depots: depots, into: dir.appendingPathComponent("G"), session: session) { _ in }
            }
        }
    }

    /// No network is not a rejected token: the login stays, the error says what happened.
    @Test func offlineIsNotALogout() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try Fixture(in: dir, mode: "offline")
            do {
                try await fixture.downloader.download(
                    appID: 331160, depots: depots, into: dir.appendingPathComponent("G"), session: session) { _ in }
                Issue.record("expected an error")
            } catch let error as DepotDownloaderError {
                guard case .failed(let status, let output) = error else { return }
                #expect(status == 1)
                #expect(output.contains("Could not connect to Steam"))
            }
        }
    }

    /// One DepotDownloader at a time: it rewrites its account store, which the next run's token write
    /// must not race (ADR 0004).
    @Test func downloadsDoNotOverlap() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try Fixture(in: dir, mode: "slow")
            let downloader = fixture.downloader
            async let first: Void = downloader.download(
                appID: 1, depots: depots, into: dir.appendingPathComponent("G1"), session: session) { _ in }
            async let second: Void = downloader.download(
                appID: 2, depots: depots, into: dir.appendingPathComponent("G2"), session: session) { _ in }
            _ = try await (first, second)

            let runs = try String(contentsOf: dir.appendingPathComponent("runs"), encoding: .utf8)
                .split(separator: "\n").map { $0.split(separator: " ")[0] }
            #expect(runs == ["start", "end", "start", "end"])
        }
    }

    /// Exit 0 without every depot done is not an install: seen for real when a depot was skipped.
    @Test func missingDepotIsAFailure() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try Fixture(in: dir, mode: "partial")
            do {
                try await fixture.downloader.download(
                    appID: 331160, depots: depots, into: dir.appendingPathComponent("G"), session: session) { _ in }
                Issue.record("expected an error")
            } catch let error as DepotDownloaderError {
                guard case .failed(_, let output) = error else { return }
                #expect(output.contains("331162"))
            }
        }
    }

    @Test func failureCarriesTheOutput() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try Fixture(in: dir, mode: "fail")
            do {
                try await fixture.downloader.download(
                    appID: 331160, depots: depots, into: dir.appendingPathComponent("G"), session: session) { _ in }
                Issue.record("expected an error")
            } catch let error as DepotDownloaderError {
                #expect(error == .failed(status: 1, output: "something broke"))
            }
        }
    }

    @Test func cancelStopsTheDownload() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try Fixture(in: dir, mode: "sleep")
            let downloader = fixture.downloader
            let task = Task {
                try await downloader.download(
                    appID: 331160, depots: depots, into: dir.appendingPathComponent("G"), session: session) { _ in }
            }
            try await Task.sleep(for: .milliseconds(300))
            let cancelled = ContinuousClock.now
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(ContinuousClock.now - cancelled < .seconds(5))
        }
    }

    @Test func toolInstallsFromTheZipAndFindsItsStore() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = Paths(root: dir.appendingPathComponent("PortGames"), cache: dir.appendingPathComponent("Cache"))
            let isolated = dir.appendingPathComponent("IsolatedStorage", isDirectory: true)
            // Someone else's .NET store is already there; ours must still be told apart.
            try FileManager.default.createDirectory(
                at: isolated.appendingPathComponent("o1/o2/Url.other/AssemFiles"), withIntermediateDirectories: true)

            let source = dir.appendingPathComponent("zip-src", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            _ = try makeFakeBinary(in: source, store: dir.appendingPathComponent("unused"), isolatedRoot: isolated)
            try Data("GPL".utf8).write(to: source.appendingPathComponent("LICENSE"))
            let zip = dir.appendingPathComponent("dd.zip")
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", source.path, zip.path]
            try ditto.run()
            ditto.waitUntilExit()
            let sha = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            let artifact = Artifact(file: "dd.zip", sha256: sha, url: URL(string: "https://example.invalid/dd.zip"))
            let copyZip: (URL, URL) async throws -> Void = { _, destination in
                try FileManager.default.copyItem(at: zip, to: destination)
            }

            let tool = try await DepotDownloaderTool.install(
                paths: paths, artifact: artifact, isolatedStorage: isolated, download: copyZip)

            #expect(FileManager.default.isExecutableFile(atPath: tool.binary.path))
            #expect(tool.binary.deletingLastPathComponent().deletingLastPathComponent() == paths.root.appendingPathComponent("tools"))
            #expect(tool.accountStore.file.path
                == isolated.appendingPathComponent("r1/r2/Url.fake/AssemFiles/account.config").standardizedFileURL.path)

            // A second install reuses everything (no new download, the same store).
            let again = try await DepotDownloaderTool.install(
                paths: paths, artifact: artifact, isolatedStorage: isolated) { _, _ in Issue.record("downloaded again") }
            #expect(again.accountStore.file == tool.accountStore.file)
        }
    }
}
