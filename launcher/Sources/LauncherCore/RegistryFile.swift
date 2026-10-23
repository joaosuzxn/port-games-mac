import Foundation

/// Edits the text files Wine keeps its registry in (`system.reg` and `user.reg`, at the top of a prefix).
///
/// **The prefix's Wine must be stopped while these functions run.** wineserver holds the registry in
/// memory and writes it back when it exits, so an edit made while it runs is lost. Callers stop it first.
public enum RegistryFile {
    /// Writes `keys` into the prefix's registry files: `.system` keys into `system.reg`, `.user` keys
    /// into `user.reg`.
    ///
    /// A key whose section already exists gets its values set inside that section (a value of the same
    /// name is replaced); otherwise a new section is appended at the end of the file. Section and value
    /// names are matched without regard to case, as Wine does. Applying the same keys again changes
    /// nothing. Values are written in name order, so the output does not depend on dictionary order.
    ///
    /// All files are read before any is written, so a missing file leaves the prefix untouched.
    public static func apply(_ keys: [RegistryKey], prefix: URL) throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        var linesByHive: [RegistryKey.Hive: [String]] = [:]
        for key in keys {
            let current = try linesByHive[key.hive] ?? readLines(fileURL(key.hive, in: prefix))
            linesByHive[key.hive] = applying(key, to: current, timestamp: timestamp)
        }
        for (hive, lines) in linesByHive {
            let text = lines.joined(separator: "\n") + "\n"
            try text.write(to: fileURL(hive, in: prefix), atomically: true, encoding: .utf8)
        }
    }

    /// Replaces the path `old` with `new` in `system.reg` and `user.reg`, in every form Wine records it:
    /// `Z:\\Users\\x` (as written in a `.reg` file), `Z:\Users\x`, and `/Users/x` or `Z:/Users/x`.
    /// Wine stores absolute paths there (fonts, the wine-mono install source and so on), so they break
    /// when the bundle that holds the prefix moves.
    ///
    /// `old` is also tried with its symbolic links resolved, since Wine may have recorded either one.
    /// A match counts only when the path ends there: `/Games/Carros.app2` is not `/Games/Carros.app`.
    /// `new` is written as it is. A registry file that does not exist is skipped, and an empty `old`
    /// changes nothing.
    public static func replacePath(_ old: String, with new: String, prefix: URL) throws {
        guard !old.isEmpty else { return }
        var variants = [old]
        let resolved = canonicalPath(old)
        if resolved != old { variants.append(resolved) }

        var replacements: [(pattern: NSRegularExpression, template: String)] = []
        for variant in variants {
            let forms: [(String, String)] = [
                ("Z:" + variant.replacingOccurrences(of: "/", with: #"\\"#),  // .reg form: Z:\\Users\\...
                 "Z:" + new.replacingOccurrences(of: "/", with: #"\\"#)),
                ("Z:" + variant.replacingOccurrences(of: "/", with: #"\"#),  // Windows form: Z:\Users\...
                 "Z:" + new.replacingOccurrences(of: "/", with: #"\"#)),
                (variant, new),  // forward slashes: Z:/... or /...
            ]
            for (oldText, newText) in forms {
                let pattern = try NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: oldText) + #"(?![\w-])"#)
                replacements.append((pattern, NSRegularExpression.escapedTemplate(for: newText)))
            }
        }

        for hive in [RegistryKey.Hive.system, .user] {
            let file = fileURL(hive, in: prefix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let original = try String(contentsOf: file, encoding: .utf8)
            let text = NSMutableString(string: original)
            for (pattern, template) in replacements {
                pattern.replaceMatches(
                    in: text, range: NSRange(location: 0, length: text.length), withTemplate: template)
            }
            if text as String != original {
                try (text as String).write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Files

    private static func fileURL(_ hive: RegistryKey.Hive, in prefix: URL) -> URL {
        let name = switch hive {
        case .system: "system.reg"
        case .user: "user.reg"
        }
        return prefix.appendingPathComponent(name, isDirectory: false)
    }

    /// The file's lines, without the empty piece a final newline would leave.
    private static func readLines(_ file: URL) throws -> [String] {
        var lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    // MARK: - Keys and values

    /// `text` as it is written between quotes (or inside a key header) in a `.reg` file.
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func valueLine(_ name: String, _ value: RegistryValue) -> String {
        switch value {
        case .string(let text): "\"\(escape(name))\"=\"\(escape(text))\""
        case .dword(let number): "\"\(escape(name))\"=dword:\(String(format: "%08x", number))"
        }
    }

    private static func applying(_ key: RegistryKey, to lines: [String], timestamp: Int) -> [String] {
        let header = "[" + escape(key.key) + "]"
        let entries = key.values.sorted { $0.key < $1.key }
        let lowercasedHeader = header.lowercased()

        guard let start = lines.firstIndex(where: { $0.lowercased().hasPrefix(lowercasedHeader) }) else {
            return lines + ["", "\(header) \(timestamp)"] + entries.map { valueLine($0.key, $0.value) }
        }

        // The section runs up to the next header, or to the end of the file.
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("[") } ?? lines.count
        var section = Array(lines[(start + 1)..<end])
        for (name, value) in entries {
            let linePrefix = "\"\(escape(name))\"=".lowercased()
            section.removeAll { $0.lowercased().hasPrefix(linePrefix) }
            while section.last == "" { section.removeLast() }
            section.append(valueLine(name, value))
        }
        if end < lines.count { section.append("") }  // keep one blank line before the next section
        return Array(lines[...start]) + section + Array(lines[end...])
    }

    // MARK: - Paths

    /// `path` with its symbolic links resolved. The part that does not exist yet is kept as it is, so a
    /// path to a bundle that has not been created resolves through its existing folders.
    private static func canonicalPath(_ path: String) -> String {
        var existing = path
        var missing: [String] = []
        while true {
            if let resolved = realPath(existing) {
                guard !missing.isEmpty else { return resolved }
                return (resolved == "/" ? "" : resolved) + "/" + missing.reversed().joined(separator: "/")
            }
            guard existing != "/", let slash = existing.lastIndex(of: "/") else { return path }
            missing.append(String(existing[existing.index(after: slash)...]))
            existing = slash == existing.startIndex ? "/" : String(existing[..<slash])
        }
    }

    private static func realPath(_ path: String) -> String? {
        path.withCString { pointer in
            guard let resolved = realpath(pointer, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}
