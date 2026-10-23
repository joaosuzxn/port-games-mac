import Foundation
import Testing
@testable import LauncherCore

// Fixtures use raw strings so a `.reg` line reads exactly as it sits in the file:
// `\\` in the text is two backslashes on disk.

private let systemRegText = #"""
WINE REGISTRY Version 2
;; All keys relative to \\Machine

[Software\\Wine\\Drives] 1700000000
#time=1
"c:"="hd"

[System\\Other] 1700000000
"x"=dword:00000002

"""#

private let userRegText = #"""
WINE REGISTRY Version 2
;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

"""#

/// A prefix folder holding a minimal `system.reg` and `user.reg`.
private func makePrefix(in dir: URL) throws -> URL {
    let prefix = dir.appendingPathComponent("prefix", isDirectory: true)
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    try systemRegText.write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
    try userRegText.write(to: prefix.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
    return prefix
}

private func readReg(_ prefix: URL, _ name: String) throws -> String {
    try String(contentsOf: prefix.appendingPathComponent(name), encoding: .utf8)
}

private func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

@Suite("RegistryFile.apply")
struct RegistryApplyTests {
    @Test func appendsToExistingSection() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply([
                RegistryKey(hive: .system, key: #"Software\Wine\Drives"#, values: ["d:": .string("cdrom")]),
                RegistryKey(hive: .system, key: #"System\CurrentControlSet\Services\winebus"#,
                            values: ["Enable SDL": .dword(1)]),
                RegistryKey(hive: .user, key: #"Software\Wine\Explorer"#, values: ["Desktop": .string("Default")]),
            ], prefix: prefix)

            let system = try readReg(prefix, "system.reg")
            #expect(system.contains(#""c:"="hd""#))
            #expect(system.contains(#""d:"="cdrom""#))
            #expect(system.contains(#"[System\\CurrentControlSet\\Services\\winebus]"#))
            #expect(system.contains(#""Enable SDL"=dword:00000001"#))
            #expect(system.contains(#""x"=dword:00000002"#))
            #expect(try readReg(prefix, "user.reg").contains(#"[Software\\Wine\\Explorer]"#))

            // The new value goes into the existing section, not into a new one.
            let afterHeader = try #require(system.components(separatedBy: #"[Software\\Wine\\Drives]"#).dropFirst().first)
            let section = try #require(afterHeader.components(separatedBy: "\n[").first)
            #expect(section.contains(#""d:"="cdrom""#))
            #expect(occurrences(of: #"[Software\\Wine\\Drives]"#, in: system) == 1)
        }
    }

    @Test func keepsTheBlankLineBeforeTheNextSection() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply(
                [RegistryKey(hive: .system, key: #"Software\Wine\Drives"#, values: ["d:": .string("cdrom")])],
                prefix: prefix)

            let expected = #"""
            WINE REGISTRY Version 2
            ;; All keys relative to \\Machine

            [Software\\Wine\\Drives] 1700000000
            #time=1
            "c:"="hd"
            "d:"="cdrom"

            [System\\Other] 1700000000
            "x"=dword:00000002

            """#
            #expect(try readReg(prefix, "system.reg") == expected)
        }
    }

    @Test func createsSection() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply(
                [RegistryKey(hive: .user, key: #"Software\Wine\Explorer"#, values: ["Desktop": .string("Default")])],
                prefix: prefix)

            let user = try readReg(prefix, "user.reg")
            // Everything that was there stays; the new section follows after one blank line.
            #expect(user.hasPrefix(userRegText))
            let added = String(user.dropFirst(userRegText.count))
            #expect(added.hasPrefix("\n"))  // the blank line
            let lines = added.dropFirst().components(separatedBy: "\n")
            #expect(lines.count == 3)  // header, value, empty piece after the final newline
            let header = try #require(lines.first)
            #expect(header.hasPrefix(#"[Software\\Wine\\Explorer] "#))
            // Wine writes the last-write time (seconds since the epoch) after the header.
            let stamp = try #require(Int(header.dropFirst(#"[Software\\Wine\\Explorer] "#.count)))
            #expect(abs(Double(stamp) - Date().timeIntervalSince1970) < 60)
            #expect(lines[1] == #""Desktop"="Default""#)
            #expect(user.hasSuffix("\n"))
            #expect(!user.hasSuffix("\n\n"))
        }
    }

    @Test func createsSectionInAFileWithoutTrailingNewlineOrAnyContent() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try "".write(to: prefix.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
            try RegistryFile.apply(
                [RegistryKey(hive: .user, key: "K", values: ["a": .dword(1)])],
                prefix: prefix)

            let lines = try readReg(prefix, "user.reg").components(separatedBy: "\n")
            #expect(lines.count == 4)  // empty line, header, value, piece after the final newline
            #expect(lines[1].hasPrefix("[K] "))
            #expect(lines[2] == #""a"=dword:00000001"#)
        }
    }

    @Test func idempotent() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            let keys = [
                RegistryKey(hive: .system, key: #"Software\Wine\Drives"#, values: ["d:": .string("cdrom")]),
                RegistryKey(hive: .user, key: #"Software\Wine\Explorer\Desktops"#,
                            values: ["Default": .string("1280x720")]),
            ]
            try RegistryFile.apply(keys, prefix: prefix)
            let systemOnce = try readReg(prefix, "system.reg")
            let userOnce = try readReg(prefix, "user.reg")
            try RegistryFile.apply(keys, prefix: prefix)

            // Applying the same keys again changes nothing at all.
            #expect(try readReg(prefix, "system.reg") == systemOnce)
            #expect(try readReg(prefix, "user.reg") == userOnce)
            #expect(occurrences(of: #"[Software\\Wine\\Drives]"#, in: systemOnce) == 1)
            #expect(occurrences(of: #""d:"="#, in: systemOnce) == 1)
        }
    }

    @Test func replacesValue() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            let desktops = #"Software\Wine\Explorer\Desktops"#
            try RegistryFile.apply(
                [RegistryKey(hive: .user, key: desktops, values: ["Default": .string("1280x720")])], prefix: prefix)
            try RegistryFile.apply(
                [RegistryKey(hive: .user, key: desktops, values: ["Default": .string("2560x1664")])], prefix: prefix)

            let user = try readReg(prefix, "user.reg")
            #expect(occurrences(of: #"[Software\\Wine\\Explorer\\Desktops]"#, in: user) == 1)
            #expect(occurrences(of: #""Default"="#, in: user) == 1)
            #expect(user.contains(#""Default"="2560x1664""#))
            #expect(!user.contains("1280x720"))
        }
    }

    @Test func replacesAValueOfAnotherTypeAndKeepsTheOthers() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply(
                [RegistryKey(hive: .system, key: #"System\Other"#, values: ["x": .string("now text"), "y": .dword(3)])],
                prefix: prefix)

            let system = try readReg(prefix, "system.reg")
            #expect(system.contains(#""x"="now text""#))
            #expect(!system.contains(#""x"=dword"#))
            #expect(system.contains(#""y"=dword:00000003"#))
            #expect(system.contains(#""c:"="hd""#))
        }
    }

    @Test func escapesBackslashAndQuote() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply(
                [RegistryKey(hive: .user, key: #"Soft\ware"#,
                             values: [#"a"b\c"#: .string(#"C:\Games\"Cars""#)])],
                prefix: prefix)

            let user = try readReg(prefix, "user.reg")
            #expect(user.contains(#"[Soft\\ware] "#))
            #expect(user.contains(#""a\"b\\c"="C:\\Games\\\"Cars\"""#))
        }
    }

    @Test func dwordIsEightLowercaseHexDigits() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply([
                RegistryKey(hive: .user, key: "K", values: [
                    "zero": .dword(0), "fourteen": .dword(14), "big": .dword(0xDEAD_BEEF), "max": .dword(.max),
                ]),
            ], prefix: prefix)

            let user = try readReg(prefix, "user.reg")
            #expect(user.contains(#""zero"=dword:00000000"#))
            #expect(user.contains(#""fourteen"=dword:0000000e"#))
            #expect(user.contains(#""big"=dword:deadbeef"#))
            #expect(user.contains(#""max"=dword:ffffffff"#))
        }
    }

    @Test func sectionAndValueLookupIgnoreCase() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply(
                [RegistryKey(hive: .system, key: #"software\WINE\drives"#, values: ["C:": .string("cdrom")])],
                prefix: prefix)

            let system = try readReg(prefix, "system.reg")
            #expect(system.lowercased().components(separatedBy: #"[software\\wine\\drives]"#).count == 2)
            #expect(!system.contains(#"[software\\WINE\\drives]"#))
            #expect(occurrences(of: #""c:"="#, in: system.lowercased()) == 1)
            #expect(system.contains(#""C:"="cdrom""#))
            #expect(!system.contains(#""c:"="hd""#))
        }
    }

    @Test func valuesAreWrittenInNameOrder() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            // Eight names, so a dictionary iteration order that is not sorted would very likely show up.
            let names = ["h", "d", "b", "f", "a", "g", "c", "e"]
            let values = Dictionary(uniqueKeysWithValues: names.map { ($0, RegistryValue.string($0.uppercased())) })
            try RegistryFile.apply([RegistryKey(hive: .user, key: "K", values: values)], prefix: prefix)

            let lines = try readReg(prefix, "user.reg").components(separatedBy: "\n")
            let written = lines.filter { $0.hasPrefix("\"") }
            #expect(written == names.sorted().map { #""\#($0)"="\#($0.uppercased())""# })
        }
    }

    @Test func userKeysDoNotTouchSystemReg() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try RegistryFile.apply(
                [RegistryKey(hive: .user, key: "K", values: ["a": .dword(1)])], prefix: prefix)

            #expect(try readReg(prefix, "system.reg") == systemRegText)
        }
    }

    @Test func noKeysDoesNothing() throws {
        try withScratchDirectory { dir in
            // Not even a prefix: with nothing to write, nothing is read.
            try RegistryFile.apply([], prefix: dir.appendingPathComponent("does-not-exist"))
        }
    }

    @Test func missingRegistryFileThrowsAndWritesNothing() throws {
        try withScratchDirectory { dir in
            let prefix = try makePrefix(in: dir)
            try FileManager.default.removeItem(at: prefix.appendingPathComponent("user.reg"))

            #expect(throws: (any Error).self) {
                try RegistryFile.apply([
                    RegistryKey(hive: .system, key: "S", values: ["a": .dword(1)]),
                    RegistryKey(hive: .user, key: "U", values: ["b": .dword(2)]),
                ], prefix: prefix)
            }
            // The system.reg change was not written either: a failed call leaves the prefix as it was.
            #expect(try readReg(prefix, "system.reg") == systemRegText)
        }
    }
}

@Suite("RegistryFile.replacePath")
struct RegistryReplacePathTests {
    private let newPath = "/Applications/Carros.app"

    /// A prefix whose `.reg` files mention the old bundle path in every form Wine records it.
    /// The folder name has a space and a non-ASCII character on purpose.
    private func makeFixture(in dir: URL) throws -> (prefix: URL, old: String) {
        let prefix = dir.appendingPathComponent("prefix", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let old = dir.appendingPathComponent("build with space ü", isDirectory: true)
            .appendingPathComponent("Carros.app", isDirectory: true).path
        let escaped = "Z:" + old.replacingOccurrences(of: "/", with: #"\\"#)  // .reg form: Z:\\Users\\...
        let single = "Z:" + old.replacingOccurrences(of: "/", with: "\\")  // plain Windows form: Z:\Users\...
        try #"""
            [Software\\Microsoft\\Fonts] 1
            "Marlett"="\#(escaped)\\Contents\\fonts\\marlett.ttf"
            "Single"="\#(single)\Contents"

            """#.write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        try #"""
            "InstallSource"="\#(old)/Contents/mono"
            "Slash"="Z:\#(old)/x"
            "Without"="C:\\windows"

            """#.write(to: prefix.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)
        return (prefix, old)
    }

    @Test func replacePathAllForms() throws {
        try withScratchDirectory { dir in
            let (prefix, old) = try makeFixture(in: dir)
            try RegistryFile.replacePath(old, with: newPath, prefix: prefix)

            let system = try readReg(prefix, "system.reg")
            let user = try readReg(prefix, "user.reg")
            #expect(system.contains(#""Marlett"="Z:\\Applications\\Carros.app\\Contents\\fonts\\marlett.ttf""#))
            #expect(system.contains(#""Single"="Z:\Applications\Carros.app\Contents""#))
            #expect(!system.contains("build with"))
            #expect(user.contains(#""InstallSource"="/Applications/Carros.app/Contents/mono""#))
            #expect(user.contains(#""Slash"="Z:/Applications/Carros.app/x""#))
            #expect(user.contains(#""Without"="C:\\windows""#))
            #expect(!user.contains("build with"))
        }
    }

    @Test func doesNotTouchSimilarNames() throws {
        try withScratchDirectory { dir in
            let prefix = dir.appendingPathComponent("prefix", isDirectory: true)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            let old = dir.appendingPathComponent("Carros.app").path
            let doubled = "Z:" + old.replacingOccurrences(of: "/", with: #"\\"#)
            let text = #"""
                "a"="\#(doubled)2\\x"
                "b"="\#(old)2/x"
                "c"="Z:\#(old)-beta/x"
                "d"="\#(old)_old"
                "e"="\#(old)"

                """#
            try text.write(to: prefix.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)

            try RegistryFile.replacePath(old, with: newPath, prefix: prefix)

            let expected = #"""
                "a"="\#(doubled)2\\x"
                "b"="\#(old)2/x"
                "c"="Z:\#(old)-beta/x"
                "d"="\#(old)_old"
                "e"="/Applications/Carros.app"

                """#
            #expect(try readReg(prefix, "user.reg") == expected)
        }
    }

    @Test func acceptsUnresolvedPath() throws {
        try withScratchDirectory { dir in
            let prefix = dir.appendingPathComponent("prefix", isDirectory: true)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            let real = dir.appendingPathComponent("real", isDirectory: true)
                .appendingPathComponent("Carros.app", isDirectory: true)
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
            let link = dir.appendingPathComponent("shortcut.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            // Wine recorded the resolved path, while the caller knows the bundle by the link.
            try "\"x\"=\"\(resolvedPath(real))/Contents\"\n"
                .write(to: prefix.appendingPathComponent("user.reg"), atomically: true, encoding: .utf8)

            try RegistryFile.replacePath(link.path, with: newPath, prefix: prefix)

            #expect(try readReg(prefix, "user.reg") == "\"x\"=\"/Applications/Carros.app/Contents\"\n")
        }
    }

    @Test func newPathIsTakenLiterally() throws {
        try withScratchDirectory { dir in
            let (prefix, old) = try makeFixture(in: dir)
            // `$1` and `&` mean something in a regex replacement template; here they are plain text.
            try RegistryFile.replacePath(old, with: "/Applications/Cars $1 & Co.app", prefix: prefix)

            #expect(try readReg(prefix, "user.reg").contains(#""InstallSource"="/Applications/Cars $1 & Co.app/Contents/mono""#))
            #expect(try readReg(prefix, "system.reg").contains(
                #""Marlett"="Z:\\Applications\\Cars $1 & Co.app\\Contents\\fonts\\marlett.ttf""#))
        }
    }

    @Test func missingFilesAreSkipped() throws {
        try withScratchDirectory { dir in
            let (prefix, old) = try makeFixture(in: dir)
            try FileManager.default.removeItem(at: prefix.appendingPathComponent("user.reg"))

            try RegistryFile.replacePath(old, with: newPath, prefix: prefix)

            let system = try readReg(prefix, "system.reg")
            #expect(!system.contains("build with"))
            #expect(!FileManager.default.fileExists(atPath: prefix.appendingPathComponent("user.reg").path))
        }
    }

    @Test func emptyOldPathChangesNothing() throws {
        try withScratchDirectory { dir in
            let (prefix, _) = try makeFixture(in: dir)
            let before = try readReg(prefix, "system.reg")

            try RegistryFile.replacePath("", with: newPath, prefix: prefix)

            #expect(try readReg(prefix, "system.reg") == before)
        }
    }
}

/// The real path of an existing file, with every symbolic link (including `/var` -> `/private/var`) resolved.
private func resolvedPath(_ url: URL) -> String {
    url.path.withCString { pointer in
        guard let resolved = realpath(pointer, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
