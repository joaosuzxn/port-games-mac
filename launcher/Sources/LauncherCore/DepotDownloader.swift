import Foundation

public enum DepotDownloaderError: Error, LocalizedError, Equatable {
    /// DepotDownloader exited with `status`; `output` is the end of what it printed.
    case failed(status: Int32, output: String)

    public var errorDescription: String? {
        switch self {
        case .failed(let status, let output):
            return "the download failed (DepotDownloader exited with \(status))" + (output.isEmpty ? "" : ": \(output)")
        }
    }
}

/// Overall progress from DepotDownloader's output: a `NN.NN% <file>` line each time a file completes,
/// cumulative within the depot announced by the last `Downloading depot <id>` line. (3.4.0 first prints
/// `Processing depot <id>` and `Downloading depot <id> manifest` for every depot while it fetches the
/// manifests, so those are not the download.) Depots weigh by their size.
struct DepotProgress {
    private let order: [UInt32]
    private let weights: [UInt32: Double]
    private let total: Double
    private var current = 0
    private var last = 0.0

    init(depots: [Depot]) {
        order = depots.map(\.id)
        let sizes = depots.map { Double($0.maxSize ?? 0) }
        let even = sizes.allSatisfy { $0 == 0 }
        weights = Dictionary(uniqueKeysWithValues: zip(order, sizes.map { even ? 1 : $0 }))
        total = max(weights.values.reduce(0, +), 1)
    }

    /// The new overall fraction (0…1) when `line` moves it forward, else nil.
    mutating func consume(_ line: String) -> Double? {
        let text = Self.stripEscapes(line).trimmingCharacters(in: .whitespaces)
        if let match = text.wholeMatch(of: #/Downloading depot (\d+)/#) {
            if let id = UInt32(match.1), let index = order.firstIndex(of: id) { current = index }
            return nil
        }
        guard let percent = text.firstMatch(of: #/^(\d{1,3}(?:\.\d+)?)% /#).flatMap({ Double($0.1) }),
            current < order.count
        else { return nil }
        let done = order[..<current].reduce(0.0) { $0 + (weights[$1] ?? 0) }
        let value = min((done + min(percent, 100) / 100 * (weights[order[current]] ?? 0)) / total, 1)
        guard value > last else { return nil }
        last = value
        return value
    }

    /// Terminal escapes (OSC 9;4 progress, colours) that DepotDownloader may print.
    static func stripEscapes(_ line: String) -> String {
        line.replacing(#/\x{1B}\][^\x{07}\x{1B}]*(?:\x{07}|\x{1B}\\)/#, with: "")
            .replacing(#/\x{1B}\[[0-9;?]*[A-Za-z]/#, with: "")
    }
}

/// DepotDownloader (SteamRE, GPL-2.0) run as a separate program, logged in with the app's QR token
/// written into its account store beforehand (ADR 0004).
public struct DepotDownloader: DepotDownloaderProtocol {
    public let binary: URL
    public let accountStore: DepotDownloaderAccountStore
    let log: URL?

    public init(binary: URL, accountStore: DepotDownloaderAccountStore, log: URL? = nil) {
        self.binary = binary
        self.accountStore = accountStore
        self.log = log
    }

    /// Lines that mean the token itself is no good: a new QR login is needed. (`InitializeSteam failed`
    /// and `Unable to get steam3 credentials` also follow a plain network failure, so they are not here.)
    static let authFailures = ["Access token was rejected", "Enter account password for"]

    public func download(
        appID: UInt32, depots: [Depot], into dir: URL, session: SteamSession,
        progress: @Sendable (Double) -> Void
    ) async throws {
        try Task.checkCancellation()
        // One DepotDownloader at a time, from writing its store to its exit: it rewrites the store
        // itself, so a token write must never land while another one runs (ADR 0004).
        let runLock = try await FileLock.acquire(binary.deletingLastPathComponent().appendingPathComponent(".run.lock"))
        defer { runLock.release() }
        try accountStore.setToken(session.refreshToken, account: session.accountName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // One -depot with every id and one -manifest with every id, in the same order: 3.4.0 ignores a
        // repeated -depot ("Argument #7 -depot was not used.").
        var arguments = ["-app", String(appID), "-depot"] + depots.map { String($0.id) }
        let manifests = depots.compactMap(\.publicManifest)
        if manifests.count == depots.count { arguments += ["-manifest"] + manifests.map { String($0) } }
        arguments += ["-os", "windows", "-dir", dir.path, "-username", session.accountName, "-remember-password"]

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.currentDirectoryURL = binary.deletingLastPathComponent()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        let logHandle = openLog()
        defer { try? logHandle?.close() }
        logHandle?.write(Data("[\(Date().ISO8601Format())] DepotDownloader \(arguments.joined(separator: " "))\n".utf8))

        let exited = Self.exit(of: process)
        try process.run()
        var parser = DepotProgress(depots: depots)
        var tail: [String] = []
        var finished: Set<UInt32> = []
        try await withTaskCancellationHandler {
            for try await line in output.fileHandleForReading.bytes.lines {
                logHandle?.write(Data((line + "\n").utf8))
                let clean = DepotProgress.stripEscapes(line).trimmingCharacters(in: .whitespaces)
                if !clean.isEmpty { tail = Array((tail + [clean]).suffix(15)) }
                if let done = clean.firstMatch(of: #/^Depot (\d+) - Downloaded/#), let id = UInt32(done.1) {
                    finished.insert(id)
                }
                if let value = parser.consume(line) { progress(value) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        await exited()
        try Task.checkCancellation()

        guard process.terminationStatus == 0, process.terminationReason == .exit else {
            if tail.contains(where: { line in Self.authFailures.contains { line.contains($0) } }) {
                throw SteamAuthError.notLoggedIn
            }
            throw DepotDownloaderError.failed(status: process.terminationStatus, output: tail.joined(separator: "\n"))
        }
        // Exit 0 is not enough: every depot asked for must have been reported done.
        let missing = depots.map(\.id).filter { !finished.contains($0) }
        guard missing.isEmpty else {
            throw DepotDownloaderError.failed(
                status: 0, output: "depots not downloaded: \(missing.map(String.init).joined(separator: ", "))\n"
                    + tail.joined(separator: "\n"))
        }
    }

    /// Waits for `process` to end without blocking a thread (`waitUntilExit()` on a Swift concurrency
    /// thread sometimes never returned while other processes started). Call before `run()`.
    static func exit(of process: Process) -> @Sendable () async -> Void {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in continuation.finish() }
        return { for await _ in stream {} }
    }

    private func openLog() -> FileHandle? {
        guard let log else { return nil }
        try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(log.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        return fd >= 0 ? FileHandle(fileDescriptor: fd, closeOnDealloc: true) : nil
    }
}

/// Gets DepotDownloader into `tools/<release>/` (a fixed path: its account store depends on it) and
/// finds its account store.
public enum DepotDownloaderTool {
    /// No checksum is published for the release; this is the hash of the first download (ADR 0004).
    public static let artifact = Artifact(
        file: "DepotDownloader-3.4.0-macos-arm64.zip",
        sha256: "60e80c7c496f3f9a079cd3c62036b35d088c27bc0149baf38f009eb57a52f6a5",
        url: URL(string: "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-macos-arm64.zip"))

    public static func install(
        paths: Paths, artifact: Artifact = artifact,
        isolatedStorage: URL = DepotDownloaderAccountStore.defaultRoot,
        log: URL? = nil,
        download: (URL, URL) async throws -> Void = ArtifactStore.downloadWithURLSession
    ) async throws -> DepotDownloader {
        let fileManager = FileManager.default
        let folder = paths.root.appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent((artifact.file as NSString).deletingPathExtension, isDirectory: true)
        let binary = folder.appendingPathComponent("DepotDownloader")
        if !fileManager.isExecutableFile(atPath: binary.path) {
            let zip = try await ArtifactStore.ensure(artifact, cache: paths.cache, localSources: [], download: download)
            try await extract(zip, binaryTo: binary)
        }

        // Remembered after the first run, which is when .NET creates the store folder.
        let remembered = folder.appendingPathComponent("account-store.path")
        if let path = try? String(contentsOf: remembered, encoding: .utf8), !path.isEmpty {
            return DepotDownloader(binary: binary, accountStore: DepotDownloaderAccountStore(file: URL(fileURLWithPath: path)), log: log)
        }
        let before = DepotDownloaderAccountStore.assemblyFolders(under: isolatedStorage)
        try await runOnce(binary, ["-V"])
        let store = try DepotDownloaderAccountStore.locate(under: isolatedStorage, before: before)
        try Data(store.file.path.utf8).write(to: remembered, options: .atomic)
        return DepotDownloader(binary: binary, accountStore: store, log: log)
    }

    /// Unzips into a scratch folder next to `binary` and moves the executable into place.
    private static func extract(_ zip: URL, binaryTo binary: URL) async throws {
        let fileManager = FileManager.default
        let folder = binary.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let scratch = folder.appendingPathComponent(".extract-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        try await runOnce(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, scratch.path])
        guard let walker = fileManager.enumerator(at: scratch, includingPropertiesForKeys: nil),
            let found = walker.compactMap({ $0 as? URL }).first(where: { $0.lastPathComponent == "DepotDownloader" })
        else { throw DepotDownloaderError.failed(status: -1, output: "\(zip.lastPathComponent) has no DepotDownloader") }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: found.path)
        if fileManager.fileExists(atPath: binary.path) { try fileManager.removeItem(at: binary) }
        try fileManager.moveItem(at: found, to: binary)
    }

    private static func runOnce(_ executable: URL, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DepotDownloader.exit(of: process)
        try process.run()
        await exited()
        guard process.terminationStatus == 0 else {
            throw DepotDownloaderError.failed(
                status: process.terminationStatus, output: "\(executable.lastPathComponent) \(arguments.joined(separator: " "))")
        }
    }
}
