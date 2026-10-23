import Foundation
import Testing
@testable import LauncherCore

// MARK: - Protobuf writer for fixtures (what protobuf-net writes for AccountSettingsStore)

private func varint(_ value: UInt64) -> [UInt8] {
    var value = value
    var out: [UInt8] = []
    repeat {
        var byte = UInt8(value & 0x7F)
        value >>= 7
        if value != 0 { byte |= 0x80 }
        out.append(byte)
    } while value != 0
    return out
}

private func lengthDelimited(_ field: UInt64, _ bytes: [UInt8]) -> [UInt8] {
    varint(field << 3 | 2) + varint(UInt64(bytes.count)) + bytes
}

private func stringEntry(_ field: UInt64, _ key: String, _ value: String) -> [UInt8] {
    lengthDelimited(field, lengthDelimited(1, Array(key.utf8)) + lengthDelimited(2, Array(value.utf8)))
}

/// ContentServerPenalty (2: map<string,int>), LoginTokens (4), GuardData (5).
private func fixture() -> [UInt8] {
    lengthDelimited(2, lengthDelimited(1, Array("cdn.example".utf8)) + varint(2 << 3 | 0) + varint(3))
        + stringEntry(4, "joao", "old-token") + stringEntry(4, "other", "other-token")
        + stringEntry(5, "joao", "guard")
}

private func runPython(_ script: String, _ args: [String]) throws -> (Int32, String) {
    let python = Process()
    python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    python.arguments = ["-I", "-c", script] + args
    let out = Pipe()
    python.standardOutput = out
    try python.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    python.waitUntilExit()
    return (python.terminationStatus, String(decoding: data, as: UTF8.self))
}

// MARK: - Tests

@Suite("DepotDownloader account store")
struct DepotDownloaderAccountTests {
    @Test func readsLoginTokens() throws {
        let file = try AccountConfig.compress(Data(fixture()))
        #expect(try AccountConfig.loginTokens(in: file) == ["joao": "old-token", "other": "other-token"])
    }

    @Test func setTokenKeepsEverythingElse() throws {
        let original = try AccountConfig.compress(Data(fixture()))

        // DepotDownloader compares account names without case.
        let updated = try AccountConfig.settingLoginToken("new-token", account: "Joao", in: original)

        #expect(try AccountConfig.loginTokens(in: updated) == ["Joao": "new-token", "other": "other-token"])
        let fields = try AccountConfig.fields(of: AccountConfig.decompress(updated))
        // Penalties and guard data are carried over byte for byte.
        let kept = fields.filter { $0.number != 4 }.map(\.bytes)
        let expected = try AccountConfig.fields(of: Data(fixture())).filter { $0.number != 4 }.map(\.bytes)
        #expect(kept == expected)
    }

    @Test func newStoreHasOnlyTheToken() throws {
        let file = try AccountConfig.settingLoginToken("t", account: "joao", in: nil)
        #expect(try AccountConfig.loginTokens(in: file) == ["joao": "t"])
        #expect(try AccountConfig.fields(of: AccountConfig.decompress(file)).map(\.number) == [4])
    }

    /// .NET's DeflateStream is raw DEFLATE (no zlib header): checked with Python's zlib, an independent
    /// implementation, in both directions.
    @Test func rawDeflateMatchesAnotherImplementation() throws {
        try withScratchDirectory { dir in
            let ours = dir.appendingPathComponent("ours.bin")
            try AccountConfig.compress(Data(fixture())).write(to: ours)
            let (status, hex) = try runPython(
                "import sys,zlib;print(zlib.decompress(open(sys.argv[1],'rb').read(),-15).hex())", [ours.path])
            #expect(status == 0)
            #expect(hex.trimmingCharacters(in: .whitespacesAndNewlines) == Data(fixture()).map { String(format: "%02x", $0) }.joined())

            let theirs = dir.appendingPathComponent("theirs.bin")
            let (status2, _) = try runPython(
                "import sys,zlib;c=zlib.compressobj(9,zlib.DEFLATED,-15);open(sys.argv[2],'wb').write(c.compress(bytes.fromhex(sys.argv[1]))+c.flush())",
                [Data(fixture()).map { String(format: "%02x", $0) }.joined(), theirs.path])
            #expect(status2 == 0)
            #expect(try AccountConfig.loginTokens(in: Data(contentsOf: theirs)) == ["joao": "old-token", "other": "other-token"])
        }
    }

    @Test func corruptFileThrows() {
        #expect(throws: (any Error).self) { try AccountConfig.loginTokens(in: Data("not deflate at all".utf8)) }
        #expect(throws: AccountConfigError.self) {
            try AccountConfig.fields(of: Data([0x22, 0x50, 0x01]))  // length past the end
        }
    }

    @Test func storeWritesAtomicallyAndMerges() throws {
        try withScratchDirectory { dir in
            let file = dir.appendingPathComponent("AssemFiles/account.config")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AccountConfig.compress(Data(fixture())).write(to: file)
            let store = DepotDownloaderAccountStore(file: file)

            try store.setToken("fresh", account: "joao")

            #expect(try store.token(account: "JOAO") == "fresh")
            #expect(try AccountConfig.loginTokens(in: Data(contentsOf: file))["other"] == "other-token")
            #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["account.config"])
        }
    }

    /// Logout must not leave the refresh token behind in DepotDownloader's store.
    @Test func removingATokenKeepsEverythingElse() throws {
        try withScratchDirectory { dir in
            let file = dir.appendingPathComponent("AssemFiles/account.config")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AccountConfig.compress(Data(fixture())).write(to: file)
            let store = DepotDownloaderAccountStore(file: file)

            try store.removeToken(account: "JOAO")

            #expect(try store.token(account: "joao") == nil)
            #expect(try AccountConfig.loginTokens(in: Data(contentsOf: file)) == ["other": "other-token"])
            let rest = try AccountConfig.fields(of: AccountConfig.decompress(Data(contentsOf: file))).filter { $0.number != 4 }
            #expect(rest.map(\.bytes) == (try AccountConfig.fields(of: Data(fixture())).filter { $0.number != 4 }.map(\.bytes)))
            // Nothing to remove (no file) is fine.
            try DepotDownloaderAccountStore(file: dir.appendingPathComponent("none/account.config")).removeToken(account: "joao")
        }
    }

    /// It holds a long-lived refresh token: readable by the user only.
    @Test func storeIsPrivateToTheUser() throws {
        try withScratchDirectory { dir in
            let store = DepotDownloaderAccountStore(file: dir.appendingPathComponent("AssemFiles/account.config"))
            try store.setToken("t", account: "joao")
            let mode = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int
            #expect(mode == 0o600)
            try store.removeToken(account: "joao")
            let after = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int
            #expect(after == 0o600)
        }
    }

    @Test func locatesTheStoreCreatedByThisBinary() throws {
        try withScratchDirectory { dir in
            let root = dir.appendingPathComponent("IsolatedStorage", isDirectory: true)
            let older = root.appendingPathComponent("a1/b1/Url.old/AssemFiles", isDirectory: true)
            try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
            let before = DepotDownloaderAccountStore.assemblyFolders(under: root)

            // The binary's first run creates its own folder.
            let ours = root.appendingPathComponent("a1/b1/Url.new/AssemFiles", isDirectory: true)
            try FileManager.default.createDirectory(at: ours, withIntermediateDirectories: true)

            let store = try DepotDownloaderAccountStore.locate(under: root, before: before)
            #expect(store.file.path == ours.appendingPathComponent("account.config").path)
        }
    }

    @Test func ambiguousStoreIsAnError() throws {
        try withScratchDirectory { dir in
            let root = dir.appendingPathComponent("IsolatedStorage", isDirectory: true)
            for name in ["Url.one", "Url.two"] {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent("a/b/\(name)/AssemFiles"), withIntermediateDirectories: true)
            }
            let all = DepotDownloaderAccountStore.assemblyFolders(under: root)
            // Nothing new appeared and there is more than one candidate: no guessing.
            #expect(throws: AccountConfigError.self) { try DepotDownloaderAccountStore.locate(under: root, before: all) }
        }
    }
}
