import Foundation
import Testing
@testable import LauncherCore

private let engineID = "ws12-wine-sikarugir-11.0_1"

private func makePaths(in dir: URL) -> Paths {
    Paths(
        root: dir.appendingPathComponent("PortGames", isDirectory: true),
        cache: dir.appendingPathComponent("Cache", isDirectory: true))
}

private func write(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

/// A published bridge with the fake DLLs, a fake `.so` and a fake `steam.exe`.
private func publishFakeBridge(_ paths: Paths) throws {
    let folder = paths.bridge.appendingPathComponent(engineID)
    try write(Data("so".utf8), to: folder.appendingPathComponent("lsteamclient.so"))
    try write(makeFakeBridge(machine: PEForwarder.i386), to: folder.appendingPathComponent("i386-windows/lsteamclient.dll"))
    try write(makeFakeBridge(), to: folder.appendingPathComponent("x86_64-windows/lsteamclient.dll"))
    try write(Data("stub".utf8), to: folder.appendingPathComponent("steam.exe"))
}

@Suite("Bridge")
struct BridgeTests {
    @Test func stageLayout() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            try publishFakeBridge(paths)
            let engine = Engine(id: engineID, root: dir.appendingPathComponent("engine", isDirectory: true))
            let prefix = dir.appendingPathComponent("prefix", isDirectory: true)

            try Bridge(paths: paths, engineID: engineID).stage(into: engine, prefix: prefix)

            let wineLib = engine.root.appendingPathComponent("wine/lib/wine")
            let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")
            for file in [
                wineLib.appendingPathComponent("x86_64-unix/lsteamclient.so"),
                wineLib.appendingPathComponent("x86_64-windows/lsteamclient.dll"),
                wineLib.appendingPathComponent("i386-windows/lsteamclient.dll"),
                prefix.appendingPathComponent("drive_c/windows/system32/lsteamclient.dll"),
                prefix.appendingPathComponent("drive_c/windows/syswow64/lsteamclient.dll"),
                steam.appendingPathComponent("steam.exe"),
            ] {
                #expect(FileManager.default.fileExists(atPath: file.path), "\(file.path)")
            }
            // 32-bit games look in Steam/, 64-bit ones in bin64/ or for steamclient64.dll.
            #expect(try PEImage(Data(contentsOf: steam.appendingPathComponent("steamclient.dll"))).machine == PEForwarder.i386)
            for name in ["bin64/steamclient.dll", "steamclient64.dll"] {
                let forwarder = try PEImage(Data(contentsOf: steam.appendingPathComponent(name)))
                #expect(forwarder.machine == PEForwarder.x86_64)
                #expect(try forwarder.exports().allSatisfy { $0.forward?.hasPrefix("lsteamclient.") == true })
            }
            // The 32-bit DLL goes to syswow64, the 64-bit one to system32.
            #expect(try PEImage(Data(contentsOf: prefix.appendingPathComponent("drive_c/windows/syswow64/lsteamclient.dll"))).machine
                == PEForwarder.i386)
        }
    }

    @Test func stagingTwiceIsFine() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            try publishFakeBridge(paths)
            let engine = Engine(id: engineID, root: dir.appendingPathComponent("engine", isDirectory: true))
            let bridge = try Bridge(paths: paths, engineID: engineID)

            try bridge.stage(into: engine, prefix: dir.appendingPathComponent("prefix"))
            try bridge.stage(into: engine, prefix: dir.appendingPathComponent("prefix"))
        }
    }

    /// The engine is shared: a game of another prefix may have these files mapped. Staging again with
    /// the same bridge must leave them alone (same file, not a new one in its place).
    @Test func restagingLeavesUnchangedEngineFilesAlone() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            try publishFakeBridge(paths)
            let engine = Engine(id: engineID, root: dir.appendingPathComponent("engine", isDirectory: true))
            let bridge = try Bridge(paths: paths, engineID: engineID)
            let wineLib = engine.root.appendingPathComponent("wine/lib/wine")
            let files = ["x86_64-unix/lsteamclient.so", "x86_64-windows/lsteamclient.dll", "i386-windows/lsteamclient.dll"]
                .map { wineLib.appendingPathComponent($0) }
            func inodes() throws -> [Int] {
                try files.map { try FileManager.default.attributesOfItem(atPath: $0.path)[.systemFileNumber] as! Int }
            }

            try bridge.stage(into: engine, prefix: dir.appendingPathComponent("prefix1"))
            let before = try inodes()
            try bridge.stage(into: engine, prefix: dir.appendingPathComponent("prefix2"))

            #expect(try inodes() == before)
        }
    }

    /// The signature comes off before the library is in place, so no Wine ever loads a signed copy.
    @Test func unixLibraryIsUnsignedWhenItLands() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            try publishFakeBridge(paths)
            // A real signed Mach-O stands in for lsteamclient.so.
            try FileManager.default.removeItem(at: paths.bridge.appendingPathComponent("\(engineID)/lsteamclient.so"))
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: "/usr/bin/true"),
                to: paths.bridge.appendingPathComponent("\(engineID)/lsteamclient.so"))
            let engine = Engine(id: engineID, root: dir.appendingPathComponent("engine", isDirectory: true))

            try Bridge(paths: paths, engineID: engineID).stage(into: engine, prefix: dir.appendingPathComponent("prefix"))

            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["-v", engine.root.appendingPathComponent("wine/lib/wine/x86_64-unix/lsteamclient.so").path]
            codesign.standardError = FileHandle.nullDevice
            try codesign.run()
            codesign.waitUntilExit()
            #expect(codesign.terminationStatus != 0, "still signed")
            // Nothing temporary is left next to it.
            let left = try FileManager.default.contentsOfDirectory(
                atPath: engine.root.appendingPathComponent("wine/lib/wine/x86_64-unix").path)
            #expect(left == ["lsteamclient.so"])
        }
    }

    /// A bridge DLL that is not a usable PE is refused before anything is written.
    @Test func badBridgeChangesNothing() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            try publishFakeBridge(paths)
            try Data("not a PE".utf8).write(to: paths.bridge.appendingPathComponent("\(engineID)/x86_64-windows/lsteamclient.dll"))
            let engine = Engine(id: engineID, root: dir.appendingPathComponent("engine", isDirectory: true))

            #expect(throws: PEForwarderError.self) {
                try Bridge(paths: paths, engineID: engineID).stage(into: engine, prefix: dir.appendingPathComponent("prefix"))
            }
            #expect(!FileManager.default.fileExists(atPath: engine.root.path))
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("prefix").path))
        }
    }

    @Test func missingBridgeIsClearError() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            do {
                _ = try Bridge(paths: paths, engineID: engineID)
                Issue.record("expected an error")
            } catch {
                #expect(error.localizedDescription.contains("build_bridge.sh"))
                #expect(error.localizedDescription.contains("lsteamclient.so"))
            }
        }
    }

    @Test func environment() {
        #expect(Bridge.environment(appID: 331160, home: URL(fileURLWithPath: "/H")) == [
            "SteamAppId": "331160",
            "SteamGameId": "331160",
            "STEAM_COMPAT_CLIENT_INSTALL_PATH": "/H/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS",
        ])
    }
}
