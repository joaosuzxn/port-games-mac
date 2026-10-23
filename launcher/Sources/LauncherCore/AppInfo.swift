import Foundation

/// What the Mac's Steam knows about one app, from its `appcache/appinfo.vdf`.
public struct AppInfo: Equatable, Sendable {
    public var appID: UInt32
    public var name: String
    public var oslist: [String]
    /// Launch options, in Steam's order.
    public var launch: [LaunchEntry]
    public var publicBuildID: UInt64?
    /// Depots with their own content (not the branch list or settings), by ID.
    public var depots: [Depot]

    /// The first launch option for Windows: one whose `oslist` is empty or names Windows.
    public var windowsLaunch: LaunchEntry? {
        launch.first { $0.oslist.isEmpty || $0.oslist.contains("windows") }
    }
}

public struct LaunchEntry: Equatable, Sendable {
    public var executable: String
    public var arguments: String
    public var oslist: [String]
}

public struct Depot: Equatable, Sendable {
    public var id: UInt32
    public var oslist: [String]
    public var osarch: String?
    public var publicManifest: UInt64?
    /// Bytes on disk once downloaded, when Steam says.
    public var maxSize: UInt64?
    /// Set on language packs (`english`, `french`, …): download only the one wanted.
    public var language: String? = nil
    /// The app this depot really belongs to (`depotfromapp`), e.g. a redistributable.
    public var fromApp: UInt32? = nil
    /// Installed once and shared between games (`sharedinstall`); no manifest of its own here.
    public var shared: Bool = false
    /// The DLC this depot is content of (`dlcappid`); not part of the base game.
    public var dlcAppID: UInt32? = nil
}

public enum AppInfoError: Error, LocalizedError, Equatable {
    case unsupportedVersion(UInt32)
    case truncated
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let magic):
            return "unsupported appinfo.vdf version (magic 0x\(String(magic, radix: 16)))"
        case .truncated: return "appinfo.vdf is truncated"
        case .malformed(let detail): return "appinfo.vdf is malformed: \(detail)"
        }
    }
}

/// Reads Steam's binary `appinfo.vdf`: v28 (keys written inline) and v29 (keys as indexes into a string
/// table at the end of the file).
///
/// ```
/// magic u32, universe u32, [v29: string table offset u64]
/// per app: appid u32 (0 ends), size u32 (bytes after this field), infostate u32, lastupdated u32,
///          picstoken u64, sha1[20], changenumber u32, binary sha1[20], binary KeyValues
/// [v29: string count u32, strings NUL-terminated]
/// ```
public enum AppInfoReader {
    static let v28: UInt32 = 0x0756_4428
    static let v29: UInt32 = 0x0756_4429

    public static func read(_ url: URL) throws -> [UInt32: AppInfo] {
        var reader = ByteReader(bytes: [UInt8](try Data(contentsOf: url)))
        let magic = try reader.u32()
        guard magic == v28 || magic == v29 else { throw AppInfoError.unsupportedVersion(magic) }
        _ = try reader.u32()  // universe

        var keys: [String]?
        if magic == v29 {
            let tableOffset = try reader.u64()
            guard tableOffset <= UInt64(reader.bytes.count) else { throw AppInfoError.truncated }
            var table = ByteReader(bytes: reader.bytes, position: Int(tableOffset))
            let count = try table.u32()
            guard UInt64(count) <= UInt64(reader.bytes.count) else { throw AppInfoError.truncated }
            keys = try (0..<count).map { _ in try table.cString() }
        }

        var apps: [UInt32: AppInfo] = [:]
        while true {
            let appID = try reader.u32()
            if appID == 0 { break }
            let size = Int(try reader.u32())
            let end = reader.position + size
            guard end <= reader.bytes.count else { throw AppInfoError.truncated }
            try reader.skip(4 + 4 + 8 + 20 + 4 + 20)
            var entry = ByteReader(bytes: reader.bytes, position: reader.position, limit: end)
            let tree = try KeyValues.parseMap(&entry, keys: keys, depth: 0)
            apps[appID] = AppInfo(appID: appID, tree: tree)
            reader.position = end
        }
        return apps
    }
}

extension AppInfo {
    init(appID: UInt32, tree: KeyValues) {
        let info = tree["appinfo"] ?? tree
        let common = info["common"]
        self.appID = appID
        name = common?["name"]?.string ?? ""
        oslist = Self.list(common?["oslist"]?.string)

        let launchEntries = info["config"]?["launch"]?.entries ?? []
        launch = launchEntries
            .sorted { (Int($0.0) ?? .max) < (Int($1.0) ?? .max) }
            .compactMap { _, option in
                guard let executable = option["executable"]?.string, !executable.isEmpty else { return nil }
                return LaunchEntry(
                    executable: executable, arguments: option["arguments"]?.string ?? "",
                    oslist: Self.list(option["config"]?["oslist"]?.string))
            }

        let depotsTree = info["depots"]
        publicBuildID = depotsTree?["branches"]?["public"]?["buildid"]?.number
        depots = (depotsTree?.entries ?? []).compactMap { key, depot in
            guard let id = UInt32(key), depot.entries != nil else { return nil }
            let manifest = depot["manifests"]?["public"]
            return Depot(
                id: id, oslist: Self.list(depot["config"]?["oslist"]?.string),
                osarch: depot["config"]?["osarch"]?.string,
                publicManifest: manifest?["gid"]?.number ?? manifest?.number,
                maxSize: depot["maxsize"]?.number ?? manifest?["size"]?.number,
                language: depot["config"]?["language"]?.string.flatMap { $0.isEmpty ? nil : $0.lowercased() },
                fromApp: depot["depotfromapp"]?.number.flatMap { UInt32(exactly: $0) },
                shared: (depot["sharedinstall"]?.number ?? 0) != 0,
                dlcAppID: depot["dlcappid"]?.number.flatMap { UInt32(exactly: $0) })
        }.sorted { $0.id < $1.id }
    }

    private static func list(_ text: String?) -> [String] {
        (text ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}

/// A binary KeyValues value.
indirect enum KeyValues: Equatable {
    case map([(String, KeyValues)])
    case string(String)
    case int(Int64)
    case uint64(UInt64)
    case float(Float)

    static func == (a: KeyValues, b: KeyValues) -> Bool {
        switch (a, b) {
        case (.map(let x), .map(let y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.string(let x), .string(let y)): return x == y
        case (.int(let x), .int(let y)): return x == y
        case (.uint64(let x), .uint64(let y)): return x == y
        case (.float(let x), .float(let y)): return x == y
        default: return false
        }
    }

    var entries: [(String, KeyValues)]? {
        if case .map(let entries) = self { return entries }
        return nil
    }

    /// Child by key, ignoring case as Steam does.
    subscript(key: String) -> KeyValues? {
        entries?.first { $0.0.caseInsensitiveCompare(key) == .orderedSame }?.1
    }

    var string: String? {
        switch self {
        case .string(let text): return text
        case .int(let value): return String(value)
        case .uint64(let value): return String(value)
        default: return nil
        }
    }

    /// Numbers come as int32, uint64 or decimal strings, depending on the field and the Steam version.
    var number: UInt64? {
        switch self {
        case .string(let text): return UInt64(text)
        case .int(let value): return value >= 0 ? UInt64(value) : nil
        case .uint64(let value): return value
        default: return nil
        }
    }

    /// Reads entries up to the end marker. `keys` is the v29 string table (nil for v28: inline keys).
    static func parseMap(_ reader: inout ByteReader, keys: [String]?, depth: Int) throws -> KeyValues {
        guard depth < 64 else { throw AppInfoError.malformed("nested too deep") }
        var entries: [(String, KeyValues)] = []
        while true {
            let type = try reader.u8()
            if type == 0x08 || type == 0x0B { return .map(entries) }
            let key: String
            if let keys {
                let index = Int(try reader.u32())
                guard index < keys.count else { throw AppInfoError.malformed("key index \(index) out of range") }
                key = keys[index]
            } else {
                key = try reader.cString()
            }
            switch type {
            case 0x00: entries.append((key, try parseMap(&reader, keys: keys, depth: depth + 1)))
            case 0x01: entries.append((key, .string(try reader.cString())))
            case 0x02, 0x04, 0x06: entries.append((key, .int(Int64(Int32(bitPattern: try reader.u32())))))
            case 0x03: entries.append((key, .float(Float(bitPattern: try reader.u32()))))
            case 0x05: entries.append((key, .string(try reader.wideString())))
            case 0x07: entries.append((key, .uint64(try reader.u64())))
            case 0x0A: entries.append((key, .int(Int64(bitPattern: try reader.u64()))))
            default: throw AppInfoError.malformed("unknown value type \(type)")
            }
        }
    }
}

/// Little-endian reads that throw `AppInfoError.truncated` instead of reading past `limit`.
struct ByteReader {
    let bytes: [UInt8]
    var position: Int
    let limit: Int

    init(bytes: [UInt8], position: Int = 0, limit: Int? = nil) {
        self.bytes = bytes
        self.position = position
        self.limit = min(limit ?? bytes.count, bytes.count)
    }

    mutating func skip(_ count: Int) throws {
        guard position + count <= limit else { throw AppInfoError.truncated }
        position += count
    }

    mutating func u8() throws -> UInt8 {
        guard position < limit else { throw AppInfoError.truncated }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func u32() throws -> UInt32 {
        guard position + 4 <= limit else { throw AppInfoError.truncated }
        defer { position += 4 }
        return (0..<4).reduce(0) { $0 | UInt32(bytes[position + $1]) << (8 * $1) }
    }

    mutating func u64() throws -> UInt64 {
        guard position + 8 <= limit else { throw AppInfoError.truncated }
        defer { position += 8 }
        return (0..<8).reduce(0) { $0 | UInt64(bytes[position + $1]) << (8 * $1) }
    }

    mutating func cString() throws -> String {
        guard let end = bytes[position..<limit].firstIndex(of: 0) else { throw AppInfoError.truncated }
        defer { position = end + 1 }
        return String(decoding: bytes[position..<end], as: UTF8.self)
    }

    mutating func wideString() throws -> String {
        var units: [UInt16] = []
        while true {
            guard position + 2 <= limit else { throw AppInfoError.truncated }
            let unit = UInt16(bytes[position]) | UInt16(bytes[position + 1]) << 8
            position += 2
            if unit == 0 { return String(decoding: units, as: UTF16.self) }
            units.append(unit)
        }
    }
}
