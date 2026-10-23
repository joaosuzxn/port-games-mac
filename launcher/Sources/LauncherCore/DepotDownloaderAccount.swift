import Foundation

public enum AccountConfigError: Error, LocalizedError, Equatable {
    case malformed(String)
    /// The DepotDownloader store could not be told apart from others under IsolatedStorage.
    case storeNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let detail): return "DepotDownloader's account.config is malformed: \(detail)"
        case .storeNotFound(let detail): return "could not find DepotDownloader's account store: \(detail)"
        }
    }
}

/// DepotDownloader's `account.config` (ADR 0004): `AccountSettingsStore` serialised by protobuf-net and
/// compressed with .NET's `DeflateStream` (raw DEFLATE, no header). Field 4 is `LoginTokens`
/// (`map<string,string>`, account name → refresh token); fields 2 and 5 are other data, kept as they are.
enum AccountConfig {
    struct Field: Equatable {
        let number: UInt64
        let wireType: UInt8
        /// The whole field as written: tag and payload.
        let bytes: Data
        /// The payload of a length-delimited field.
        let payload: Data?
    }

    static let loginTokensField: UInt64 = 4

    static func decompress(_ data: Data) throws -> Data {
        try (data as NSData).decompressed(using: .zlib) as Data
    }

    static func compress(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    static func loginTokens(in file: Data) throws -> [String: String] {
        var tokens: [String: String] = [:]
        for (account, token) in try entries(in: decompress(file)) { tokens[account] = token }
        return tokens
    }

    /// The store with `token` for `account` (replacing an entry whose name differs only in case), every
    /// other field and account kept. `existing` nil: a new store.
    static func settingLoginToken(_ token: String, account: String, in existing: Data?) throws -> Data {
        let message = try existing.map(decompress) ?? Data()
        var out = Data()
        for field in try fields(of: message) where field.number != loginTokensField {
            out.append(field.bytes)
        }
        var tokens = try entries(in: message).filter { $0.0.caseInsensitiveCompare(account) != .orderedSame }
        tokens.append((account, token))
        for (name, value) in tokens {
            out.append(lengthDelimited(loginTokensField, lengthDelimited(1, Data(name.utf8)) + lengthDelimited(2, Data(value.utf8))))
        }
        return try compress(out)
    }

    /// Top-level fields in file order.
    static func fields(of message: Data) throws -> [Field] {
        let bytes = [UInt8](message)
        var position = 0
        var out: [Field] = []
        while position < bytes.count {
            let start = position
            let tag = try varint(bytes, &position)
            let wireType = UInt8(tag & 7)
            var payload: Data?
            switch wireType {
            case 0: _ = try varint(bytes, &position)
            case 1: position += 8
            case 5: position += 4
            case 2:
                let length = try varint(bytes, &position)
                guard length <= UInt64(bytes.count - position) else { throw AccountConfigError.malformed("length past the end") }
                payload = Data(bytes[position..<position + Int(length)])
                position += Int(length)
            default: throw AccountConfigError.malformed("wire type \(wireType)")
            }
            guard position <= bytes.count else { throw AccountConfigError.malformed("truncated field") }
            out.append(Field(number: tag >> 3, wireType: wireType, bytes: Data(bytes[start..<position]), payload: payload))
        }
        return out
    }

    /// The `LoginTokens` entries, in file order.
    private static func entries(in message: Data) throws -> [(String, String)] {
        try fields(of: message).filter { $0.number == loginTokensField && $0.wireType == 2 }.map { field in
            var key = "", value = ""
            for part in try fields(of: field.payload ?? Data()) where part.wireType == 2 {
                let text = String(decoding: part.payload ?? Data(), as: UTF8.self)
                if part.number == 1 { key = text } else if part.number == 2 { value = text }
            }
            return (key, value)
        }
    }

    private static func varint(_ bytes: [UInt8], _ position: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard position < bytes.count, shift < 64 else { throw AccountConfigError.malformed("bad varint") }
            let byte = bytes[position]
            position += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
    }

    private static func lengthDelimited(_ field: UInt64, _ payload: Data) -> Data {
        var out = Data()
        for number in [field << 3 | 2, UInt64(payload.count)] {
            var value = number
            repeat {
                var byte = UInt8(value & 0x7F)
                value >>= 7
                if value != 0 { byte |= 0x80 }
                out.append(byte)
            } while value != 0
        }
        return out + payload
    }
}

/// The `account.config` of one DepotDownloader binary. Write only while DepotDownloader is not running:
/// it rewrites the whole file.
public struct DepotDownloaderAccountStore: Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// Where .NET keeps it on macOS: `IsolatedStorage/<random>/<random>/Url.<hash of the binary's path>/AssemFiles`.
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/IsolatedStorage", isDirectory: true)
    }

    public func token(account: String) throws -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try AccountConfig.loginTokens(in: data)
            .first { $0.key.caseInsensitiveCompare(account) == .orderedSame }?.value
    }

    public func setToken(_ token: String, account: String) throws {
        let existing = try? Data(contentsOf: file)
        let data = try AccountConfig.settingLoginToken(token, account: account, in: existing)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// Every `AssemFiles` folder under `root`.
    public static func assemblyFolders(under root: URL) -> Set<String> {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var found: Set<String> = []
        for case let url as URL in walker where url.lastPathComponent == "AssemFiles" {
            found.insert(url.standardizedFileURL.path)
        }
        return found
    }

    /// The store of the binary that has just run for the first time: the `AssemFiles` folder that was not
    /// there `before`. With nothing new, the only folder there is; anything else is an error, not a guess.
    public static func locate(under root: URL, before: Set<String>) throws -> DepotDownloaderAccountStore {
        let now = assemblyFolders(under: root)
        let new = now.subtracting(before)
        let folder: String
        if new.count == 1 {
            folder = new.first!
        } else if new.isEmpty, now.count == 1 {
            folder = now.first!
        } else {
            throw AccountConfigError.storeNotFound("\(new.count) new and \(now.count) total folders under \(root.path)")
        }
        return DepotDownloaderAccountStore(file: URL(fileURLWithPath: folder).appendingPathComponent("account.config"))
    }
}
