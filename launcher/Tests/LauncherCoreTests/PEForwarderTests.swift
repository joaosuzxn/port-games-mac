import Foundation
import Testing
@testable import LauncherCore

/// A stand-in for `lsteamclient.dll`: real code exports (not forwards), names out of ASCII order and
/// with a gap in the ordinals, like a real DLL can have.
func makeFakeBridge(machine: UInt16 = PEForwarder.x86_64) throws -> Data {
    try PEForwarder.build(
        machine: machine,
        entries: [
            (ordinal: 1, name: "Steam_ReleaseThreadLocalMemory"), (ordinal: 2, name: "CreateInterface"),
            (ordinal: 4, name: "Breakpad_SteamSetAppID"),
        ],
        forwardTarget: nil, dllName: "lsteamclient.dll")
}

/// The bridges built by the owner, where they exist on this Mac: the published copy first, then the
/// build tree of the spike.
private func realBridges() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let folders = [
        Paths.standard.bridge.appendingPathComponent("ws12-wine-sikarugir-11.0_1"),
        home.appendingPathComponent("Library/Caches/portcarros/fontes/wine-build-dual/dlls/lsteamclient"),
    ]
    for folder in folders {
        let dlls = ["i386-windows", "x86_64-windows"].map {
            folder.appendingPathComponent("\($0)/lsteamclient.dll")
        }
        if dlls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return dlls }
    }
    return []
}

@Suite("PEForwarder")
struct PEForwarderTests {
    @Test func forwarderExportsMatch() throws {
        var bridges = [try makeFakeBridge(), try makeFakeBridge(machine: PEForwarder.i386)]
        bridges += try realBridges().map { try Data(contentsOf: $0) }

        for bridge in bridges {
            let forwarder = try PEForwarder.generate(from: bridge, target: "lsteamclient")

            #expect(try PEForwarder.exports(of: forwarder) == PEForwarder.exports(of: bridge))
            let exports = try PEImage(forwarder).exports()
            #expect(!exports.isEmpty)
            for export in exports {
                #expect(export.forward == "lsteamclient.\(export.name ?? "?")")
            }
            // Ordinals are kept, gaps included.
            let bridgeOrdinals = try PEImage(bridge).exports().map(\.ordinal)
            #expect(exports.map(\.ordinal) == bridgeOrdinals)
        }
    }

    @Test func fakeBridgeIsCode() throws {
        // The fixture must look like the real bridge: code exports, so the forwarder is what adds forwards.
        let exports = try PEImage(makeFakeBridge()).exports()
        #expect(exports.map(\.name) == ["Steam_ReleaseThreadLocalMemory", "CreateInterface", "Breakpad_SteamSetAppID"])
        #expect(exports.allSatisfy { $0.forward == nil })
    }

    @Test func forwarderHasDataArena() throws {
        let image = try PEImage(PEForwarder.generate(from: makeFakeBridge(), target: "lsteamclient"))
        let data = try #require(image.sections.first { $0.name == ".data" })
        #expect(data.virtualSize >= 0x100000)
        #expect(image.sections.map(\.name) == [".text", ".edata", ".reloc", ".data"])
    }

    @Test(arguments: [PEForwarder.i386, PEForwarder.x86_64])
    func forwarderMachineMatches(machine: UInt16) throws {
        let forwarder = try PEForwarder.generate(from: makeFakeBridge(machine: machine), target: "lsteamclient")
        #expect(try PEImage(forwarder).machine == machine)
    }

    @Test func nameTableInAsciiOrder() throws {
        let forwarder = try PEForwarder.generate(from: makeFakeBridge(), target: "lsteamclient")
        #expect(try PEImage(forwarder).nameTable()
            == ["Breakpad_SteamSetAppID", "CreateInterface", "Steam_ReleaseThreadLocalMemory"])
    }

    @Test func forwarderNamesItself() throws {
        let forwarder = try PEForwarder.generate(from: makeFakeBridge(), target: "lsteamclient")
        let image = try PEImage(forwarder)
        let directory = try #require(image.offset(image.directories[0].rva))
        #expect(try image.cString(image.bytes.u32(at: directory + 12)) == "steamclient.dll")
    }

    @Test func bridgeWithoutRequiredExportsIsRefused() throws {
        let bridge = try PEForwarder.build(
            machine: PEForwarder.x86_64, entries: [(ordinal: 1, name: "CreateInterface")],
            forwardTarget: nil, dllName: "lsteamclient.dll")
        #expect(throws: PEForwarderError.checkFailed(["does not forward Steam_ReleaseThreadLocalMemory to lsteamclient"])) {
            try PEForwarder.generate(from: bridge, target: "lsteamclient")
        }
    }

    /// Same bytes as Neutron's own `peforward.py gen`, on the real bridges (owner's Mac only).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTGAMES_INTEGRATION"] == "1"))
    func matchesNeutronByteForByte() throws {
        let script = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/portcarros/fontes/neutron/src/peforward.py")
        let bridges = realBridges()
        try #require(FileManager.default.fileExists(atPath: script.path) && !bridges.isEmpty)
        try withScratchDirectory { dir in
            for bridge in bridges {
                let expected = dir.appendingPathComponent("steamclient.dll")
                let python = Process()
                python.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                python.arguments = ["-I", script.path, "gen", bridge.path, "lsteamclient", expected.path]
                python.standardOutput = FileHandle.nullDevice
                try python.run()
                python.waitUntilExit()
                try #require(python.terminationStatus == 0)

                let generated = try PEForwarder.generate(from: Data(contentsOf: bridge), target: "lsteamclient")
                #expect(generated == (try Data(contentsOf: expected)), "\(bridge.path)")
            }
        }
    }

    @Test func notPEAndTruncatedAreErrors() throws {
        #expect(throws: PEForwarderError.notPE) { try PEForwarder.exports(of: Data("hello".utf8)) }
        let bridge = try makeFakeBridge()
        #expect(throws: PEForwarderError.self) { try PEForwarder.generate(from: bridge.prefix(0x400), target: "x") }
    }
}
