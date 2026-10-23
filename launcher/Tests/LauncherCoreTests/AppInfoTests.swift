import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fixture writer (the binary format Steam uses)

/// A binary KeyValues node, as written into `appinfo.vdf`.
private indirect enum Node {
    case map([(String, Node)])
    case string(String)
    case int32(Int32)
    case uint64(UInt64)
}

private struct Writer {
    let version: UInt32  // 28 or 29
    var strings: [String] = []
    var stringIndex: [String: UInt32] = [:]

    init(version: UInt32) { self.version = version }

    mutating func key(_ name: String, into out: inout [UInt8]) {
        if version == 28 {
            out += Array(name.utf8) + [0]
        } else {
            let index = stringIndex[name] ?? {
                strings.append(name)
                stringIndex[name] = UInt32(strings.count - 1)
                return UInt32(strings.count - 1)
            }()
            out += le(index)
        }
    }

    mutating func map(_ entries: [(String, Node)], into out: inout [UInt8]) {
        for (name, node) in entries {
            switch node {
            case .map(let children):
                out.append(0)
                key(name, into: &out)
                map(children, into: &out)
            case .string(let text):
                out.append(1)
                key(name, into: &out)
                out += Array(text.utf8) + [0]
            case .int32(let value):
                out.append(2)
                key(name, into: &out)
                out += le(UInt32(bitPattern: value))
            case .uint64(let value):
                out.append(7)
                key(name, into: &out)
                out += le(value)
            }
        }
        out.append(8)
    }

    /// The whole file with `apps` (app ID → its `appinfo` map).
    mutating func file(_ apps: [(UInt32, [(String, Node)])]) -> Data {
        var body: [UInt8] = []
        for (appID, tree) in apps {
            var kv: [UInt8] = []
            map(tree, into: &kv)
            body += le(appID)
            // Size counts everything after the size field itself.
            let header: [UInt8] = le(UInt32(2)) + le(UInt32(1_700_000_000)) + le(UInt64(0))
                + [UInt8](repeating: 0xAB, count: 20) + le(UInt32(42)) + [UInt8](repeating: 0xCD, count: 20)
            body += le(UInt32(header.count + kv.count)) + header + kv
        }
        body += le(UInt32(0))  // end of apps

        let magic: UInt32 = version == 28 ? 0x0756_4428 : 0x0756_4429
        var out = le(magic) + le(UInt32(1))
        if version == 29 {
            let tableOffset = UInt64(8 + 8 + body.count)
            out += le(tableOffset) + body + le(UInt32(strings.count))
            for name in strings { out += Array(name.utf8) + [0] }
        } else {
            out += body
        }
        return Data(out)
    }
}

private func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian) { Array($0) }
}

private let carros: [(String, Node)] = [
    ("appinfo", .map([
        ("appid", .int32(331160)),
        ("common", .map([("name", .string("Cars")), ("oslist", .string("windows"))])),
        ("config", .map([
            ("launch", .map([
                ("0", .map([
                    ("executable", .string("Cars.exe")), ("arguments", .string("-nointro")),
                    ("config", .map([("oslist", .string("windows"))])),
                ])),
            ])),
        ])),
        ("depots", .map([
            ("331161", .map([
                ("config", .map([("oslist", .string("windows"))])),
                ("manifests", .map([("public", .map([
                    ("gid", .string("7406377411530442766")), ("size", .string("1170843402")),
                ]))])),
                ("maxsize", .string("1170843402")),
            ])),
            ("228988", .map([
                ("config", .map([("oslist", .string("windows"))])),
                ("manifests", .map([("public", .uint64(5_000_000_000_000_000_001))])),
            ])),
            // The DirectX redist: shared with another app, no manifest of its own.
            ("228990", .map([
                ("config", .map([("oslist", .string("windows"))])),
                ("depotfromapp", .string("228980")), ("sharedinstall", .string("1")),
            ])),
            ("331162", .map([
                ("config", .map([("language", .string("french")), ("oslist", .string("windows"))])),
                ("manifests", .map([("public", .map([("gid", .string("99")), ("size", .string("1500000000"))]))])),
            ])),
            ("branches", .map([("public", .map([("buildid", .string("454676"))]))])),
        ])),
    ])),
]

private let rdr2: [(String, Node)] = [
    ("appinfo", .map([
        ("appid", .int32(1174180)),
        ("common", .map([("name", .string("Red Dead Redemption 2")), ("oslist", .string("windows"))])),
        ("config", .map([
            ("launch", .map([
                ("0", .map([
                    ("executable", .string("PlayRDR2.exe")),
                    ("config", .map([("oslist", .string("macos"))])),
                ])),
                ("1", .map([("executable", .string("PlayRDR2.exe")), ("arguments", .string("-vulkan"))])),
            ])),
        ])),
        ("depots", .map([
            ("1174181", .map([
                ("config", .map([("oslist", .string("windows")), ("osarch", .string("64"))])),
                ("manifests", .map([("public", .map([("gid", .string("123")), ("size", .int32(1000))]))])),
            ])),
            ("1174189", .map([
                ("dlcappid", .string("1174190")),
                ("manifests", .map([("public", .map([("gid", .string("5")), ("size", .int32(10))]))])),
            ])),
            ("branches", .map([("public", .map([("buildid", .int32(98765))]))])),
        ])),
    ])),
]

// MARK: - Tests

@Suite("AppInfo")
struct AppInfoTests {
    private func check(_ apps: [UInt32: AppInfo]) throws {
        let cars = try #require(apps[331160])
        #expect(cars.name == "Cars")
        #expect(cars.oslist == ["windows"])
        #expect(cars.launch == [LaunchEntry(executable: "Cars.exe", arguments: "-nointro", oslist: ["windows"])])
        #expect(cars.publicBuildID == 454676)
        #expect(cars.depots == [
            Depot(id: 228988, oslist: ["windows"], osarch: nil, publicManifest: 5_000_000_000_000_000_001, maxSize: nil),
            Depot(id: 228990, oslist: ["windows"], osarch: nil, publicManifest: nil, maxSize: nil,
                fromApp: 228980, shared: true),
            Depot(id: 331161, oslist: ["windows"], osarch: nil, publicManifest: 7406377411530442766, maxSize: 1170843402),
            Depot(id: 331162, oslist: ["windows"], osarch: nil, publicManifest: 99, maxSize: 1500000000,
                language: "french"),
        ])
        #expect(cars.windowsLaunch?.executable == "Cars.exe")

        let red = try #require(apps[1174180])
        #expect(red.publicBuildID == 98765)
        // The macOS entry comes first; the Windows one is the entry with no oslist.
        #expect(red.windowsLaunch == LaunchEntry(executable: "PlayRDR2.exe", arguments: "-vulkan", oslist: []))
        #expect(red.depots == [
            Depot(id: 1174181, oslist: ["windows"], osarch: "64", publicManifest: 123, maxSize: 1000),
            Depot(id: 1174189, oslist: [], osarch: nil, publicManifest: 5, maxSize: 10, dlcAppID: 1174190),
        ])
    }

    @Test func parsesV29Fixture() throws {
        try withScratchDirectory { dir in
            var writer = Writer(version: 29)
            let file = dir.appendingPathComponent("appinfo.vdf")
            try writer.file([(331160, carros), (1174180, rdr2)]).write(to: file)
            try check(AppInfoReader.read(file))
        }
    }

    @Test func parsesV28Fixture() throws {
        try withScratchDirectory { dir in
            var writer = Writer(version: 28)
            let file = dir.appendingPathComponent("appinfo.vdf")
            try writer.file([(331160, carros), (1174180, rdr2)]).write(to: file)
            try check(AppInfoReader.read(file))
        }
    }

    @Test func truncatedFileThrows() throws {
        try withScratchDirectory { dir in
            var writer = Writer(version: 29)
            let whole = writer.file([(331160, carros), (1174180, rdr2)])
            let file = dir.appendingPathComponent("appinfo.vdf")
            for length in [3, 16, 40, whole.count / 2, whole.count - 3] {
                try whole.prefix(length).write(to: file)
                #expect(throws: AppInfoError.self, "length \(length)") { try AppInfoReader.read(file) }
            }
        }
    }

    @Test func unknownVersionThrows() throws {
        try withScratchDirectory { dir in
            let file = dir.appendingPathComponent("appinfo.vdf")
            try Data(le(UInt32(0x0756_4427)) + le(UInt32(1))).write(to: file)
            #expect(throws: AppInfoError.unsupportedVersion(0x0756_4427)) { try AppInfoReader.read(file) }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PORTGAMES_INTEGRATION"] == "1"))
    func realFileSmoke() throws {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/appcache/appinfo.vdf")
        let apps = try AppInfoReader.read(file)
        let cars = try #require(apps[331160])
        #expect(cars.name == "Cars")
        #expect(cars.windowsLaunch?.executable == "Cars.exe")
        #expect(cars.publicBuildID == 454676)
        // Cars ships one depot per language and borrows the DirectX redist from another app.
        let english = try #require(cars.depots.first { $0.id == 331162 })
        #expect(english.language == "english")
        #expect(cars.depots.filter { $0.language != nil }.count > 5)
        let redist = try #require(cars.depots.first { $0.id == 228990 })
        #expect(redist.shared && redist.fromApp == 228980)
        #expect(apps[1174180]?.windowsLaunch?.executable == "PlayRDR2.exe")
    }
}
