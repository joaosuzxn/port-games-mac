// Port of `peforward.py` from Neutron (https://github.com/mont127/Neutron), Apache License 2.0.
// The layout of the generated file is the same, byte for byte.

import Foundation

public enum PEForwarderError: Error, LocalizedError, Equatable {
    case notPE
    /// An offset or string points past the end of the file.
    case truncated
    case unsupportedMachine(UInt16)
    case noNamedExports
    /// The generated forwarder, read back, is not what it must be; nothing was written.
    case checkFailed([String])

    public var errorDescription: String? {
        switch self {
        case .notPE: return "not a PE file"
        case .truncated: return "the PE file is truncated or malformed"
        case .unsupportedMachine(let machine): return "not an x86 PE (machine 0x\(String(machine, radix: 16)))"
        case .noNamedExports: return "the bridge exports nothing by name"
        case .checkFailed(let problems): return "bad forwarder: " + problems.joined(separator: "; ")
        }
    }
}

/// Builds the export-only DLL that stands in for the Steam bridge under the name `steamclient.dll`.
///
/// A game with Steam DRM loads whatever `SteamClientDll64` names and then looks the module up again as
/// the literal `steamclient.dll`. The bridge (`lsteamclient.dll`) cannot take that name: it allocates
/// its interface objects in the `.data` of the module called `steamclient.dll`, which would be its own
/// globals. So that name goes to this forwarder: every export is a forward string to the bridge, plus a
/// `.data` arena the bridge can allocate into, and a `DllMain` that returns TRUE.
public enum PEForwarder {
    static let i386: UInt16 = 0x14C
    static let x86_64: UInt16 = 0x8664

    /// `CreateInterface` is how steam_api reaches the bridge; `Steam_ReleaseThreadLocalMemory` is the one
    /// a DRM wrapper looks up by module name.
    static let required = ["CreateInterface", "Steam_ReleaseThreadLocalMemory"]

    static let sectionAlignment: UInt32 = 0x1000
    static let fileAlignment: UInt32 = 0x200
    static let textRVA: UInt32 = 0x1000
    static let edataRVA: UInt32 = 0x2000
    /// The arena the bridge allocates its interface objects into.
    static let dataSize = 0x100000

    /// `mov eax, 1; ret` (stdcall `ret 12` on i386).
    static let entry: [UInt16: [UInt8]] = [
        x86_64: [0xB8, 0x01, 0x00, 0x00, 0x00, 0xC3],
        i386: [0xB8, 0x01, 0x00, 0x00, 0x00, 0xC2, 0x0C, 0x00],
    ]

    /// Names the DLL exports, in ordinal order.
    public static func exports(of dll: Data) throws -> [String] {
        try PEImage(dll).exports().compactMap(\.name)
    }

    /// The forwarder for `bridge`: each named export of the bridge forwarded to `<target>.<name>`. It is
    /// read back and checked before it is returned.
    public static func generate(from bridge: Data, target: String, dllName: String = "steamclient.dll") throws -> Data {
        let image = try PEImage(bridge)
        guard entry[image.machine] != nil else { throw PEForwarderError.unsupportedMachine(image.machine) }
        let entries = try image.exports().compactMap { export in
            export.name.map { (ordinal: export.ordinal, name: $0) }
        }.sorted { $0.ordinal < $1.ordinal }
        guard !entries.isEmpty else { throw PEForwarderError.noNamedExports }

        let forwarder = try build(machine: image.machine, entries: entries, forwardTarget: target, dllName: dllName)
        let problems = try check(bridge: bridge, forwarder: forwarder, target: target)
        guard problems.isEmpty else { throw PEForwarderError.checkFailed(problems) }
        return forwarder
    }

    /// What is wrong with `forwarder` as a stand-in for `bridge` (empty when nothing is).
    static func check(bridge: Data, forwarder: Data, target: String) throws -> [String] {
        let b = try PEImage(bridge)
        let f = try PEImage(forwarder)
        var bad: [String] = []
        if b.machine != f.machine { bad.append("built for \(f.arch), bridge is \(b.arch)") }
        let fExports = try f.exports()
        let bNamed = Dictionary(try b.exports().compactMap { e in e.name.map { (e.ordinal, $0) } }) { a, _ in a }
        let fNamed = Dictionary(fExports.compactMap { e in e.name.map { (e.ordinal, $0) } }) { a, _ in a }
        // Every check below passes on a file that exports nothing, the one shape that must never get through.
        if fNamed.isEmpty { bad.append("exports nothing") }
        if bNamed != fNamed { bad.append("exports do not match the bridge (\(fNamed.count) vs \(bNamed.count))") }
        let forwards = Dictionary(fExports.compactMap { e in e.name.map { ($0, e.forward) } }) { a, _ in a }
        for name in required where forwards[name] != "\(target).\(name)" {
            bad.append("does not forward \(name) to \(target)")
        }
        let code = fExports.filter { $0.name != nil && $0.forward == nil }
        if !code.isEmpty { bad.append("\(code.count) exports are real code, not forwards") }
        if let wrong = fExports.compactMap(\.forward).first(where: { !$0.hasPrefix(target + ".") }) {
            bad.append("forwards somewhere else: \(wrong)")
        }
        // GetProcAddress binary-searches the name table: out of order, it misses names that are there.
        let names = try f.nameTable()
        if names != names.sorted(by: latin1Less) { bad.append("export names are not in ascii order") }
        // The bridge refuses to initialise without a `.data` to allocate into.
        if let data = f.sections.first(where: { $0.name.hasPrefix(".data") }) {
            if data.virtualSize < dataSize { bad.append("its .data is \(data.virtualSize) bytes, too small to allocate into") }
        } else {
            bad.append("has no .data, the bridge cannot allocate and refuses to init")
        }
        return bad
    }

    /// The whole image. With `forwardTarget` `nil` the exports point at the entry code instead (a stand-in
    /// for a real DLL, used by the tests).
    static func build(
        machine: UInt16, entries: [(ordinal: UInt32, name: String)], forwardTarget: String?, dllName: String
    ) throws -> Data {
        let edata = try exportSection(entries: entries, forwardTarget: forwardTarget, dllName: dllName)
        return image(machine: machine, edata: edata)
    }

    /// The export directory, its three tables and every string they point at: the `.edata` section.
    private static func exportSection(
        entries: [(ordinal: UInt32, name: String)], forwardTarget: String?, dllName: String
    ) throws -> [UInt8] {
        let base = entries.map(\.ordinal).min()!
        // Named exports index the function table through 16-bit ordinals, so a wider span is corrupt
        // (and would mean a huge table).
        let span = entries.map(\.ordinal).max()! - base
        guard span <= UInt32(UInt16.max) else { throw PEForwarderError.truncated }
        let functionCount = Int(span) + 1
        let byName = entries.sorted { latin1Less($0.name, $1.name) }
        let nameCount = byName.count

        let functionsOffset = 40
        let namesOffset = functionsOffset + functionCount * 4
        let ordinalsOffset = namesOffset + nameCount * 4
        let stringsOffset = ordinalsOffset + nameCount * 2
        var strings: [UInt8] = []
        func put(_ text: String) throws -> UInt32 {
            guard let bytes = text.data(using: .isoLatin1) else { throw PEForwarderError.checkFailed(["name not latin-1: \(text)"]) }
            let at = edataRVA + UInt32(stringsOffset + strings.count)
            strings.append(contentsOf: bytes)
            strings.append(0)
            return at
        }

        let nameRVA = try put(dllName)
        var functionRVA: [UInt32: UInt32] = [:]
        for entry in entries {
            functionRVA[entry.ordinal] = try forwardTarget.map { try put("\($0).\(entry.name)") } ?? textRVA
        }
        var nameRVAs: [String: UInt32] = [:]
        for entry in byName { nameRVAs[entry.name] = try put(entry.name) }

        var buffer = [UInt8](repeating: 0, count: stringsOffset) + strings
        buffer.put32(nameRVA, at: 12)
        buffer.put32(base, at: 16)
        buffer.put32(UInt32(functionCount), at: 20)
        buffer.put32(UInt32(nameCount), at: 24)
        buffer.put32(edataRVA + UInt32(functionsOffset), at: 28)
        buffer.put32(edataRVA + UInt32(namesOffset), at: 32)
        buffer.put32(edataRVA + UInt32(ordinalsOffset), at: 36)
        for entry in entries {
            buffer.put32(functionRVA[entry.ordinal]!, at: functionsOffset + Int(entry.ordinal - base) * 4)
        }
        for (index, entry) in byName.enumerated() {
            buffer.put32(nameRVAs[entry.name]!, at: namesOffset + index * 4)
            buffer.put16(UInt16(entry.ordinal - base), at: ordinalsOffset + index * 2)
        }
        return buffer
    }

    private static func image(machine: UInt16, edata: [UInt8]) -> Data {
        let plus = machine == x86_64
        let text = entry[machine]!
        // One relocation block with two do-nothing entries: Wine will not move an image without one.
        var reloc: [UInt8] = []
        reloc.append32(textRVA)
        reloc.append32(12)
        reloc.append16(0)
        reloc.append16(0)
        let relocRVA = edataRVA + align(UInt32(edata.count), sectionAlignment)
        let dataRVA = relocRVA + align(UInt32(reloc.count), sectionAlignment)
        let data = [UInt8](repeating: 0, count: dataSize)
        let sections: [(name: String, rva: UInt32, body: [UInt8], flags: UInt32)] = [
            (".text", textRVA, text, 0x6000_0020),
            (".edata", edataRVA, edata, 0x4000_0040),
            (".reloc", relocRVA, reloc, 0x4200_0040),
            (".data", dataRVA, data, 0xC000_0040),
        ]
        let optionalSize: UInt32 = plus ? 240 : 224
        let headers = Int(align(0x80 + 24 + optionalSize + UInt32(sections.count) * 40, fileAlignment))

        var out = [UInt8](repeating: 0, count: headers)
        out[0] = 0x4D  // "MZ"
        out[1] = 0x5A
        out.put32(0x80, at: 0x3C)
        out.put32(0x4550, at: 0x80)  // "PE\0\0"
        out.put16(machine, at: 0x84)
        out.put16(UInt16(sections.count), at: 0x86)
        out.put16(UInt16(optionalSize), at: 0x94)
        // DLL, executable; relocations kept (see above)
        out.put16(0x2002 | (plus ? 0x0020 : 0x0100), at: 0x96)
        let opt = 0x98
        out.put16(plus ? 0x20B : 0x10B, at: opt)
        out[opt + 2] = 14
        out.put32(align(UInt32(text.count), fileAlignment), at: opt + 4)
        out.put32(align(UInt32(edata.count), fileAlignment) + align(UInt32(reloc.count), fileAlignment), at: opt + 8)
        out.put32(textRVA, at: opt + 16)
        out.put32(textRVA, at: opt + 20)
        if plus {
            out.put64(0x1_8000_0000, at: opt + 24)
        } else {
            out.put32(edataRVA, at: opt + 24)
            out.put32(0x1000_0000, at: opt + 28)
        }
        out.put32(sectionAlignment, at: opt + 32)
        out.put32(fileAlignment, at: opt + 36)
        out.put16(6, at: opt + 40)
        out.put16(6, at: opt + 48)
        out.put32(dataRVA + align(UInt32(dataSize), sectionAlignment), at: opt + 56)
        out.put32(UInt32(headers), at: opt + 60)
        out.put16(3, at: opt + 68)  // console subsystem
        out.put16(0x0140, at: opt + 70)  // dynamic base, NX
        if plus {
            out.put64(0x100000, at: opt + 72)
            out.put64(0x1000, at: opt + 80)
            out.put64(0x100000, at: opt + 88)
            out.put64(0x1000, at: opt + 96)
            out.put32(16, at: opt + 108)
        } else {
            out.put32(0x100000, at: opt + 72)
            out.put32(0x1000, at: opt + 76)
            out.put32(0x100000, at: opt + 80)
            out.put32(0x1000, at: opt + 84)
            out.put32(16, at: opt + 92)
        }
        let directories = opt + (plus ? 112 : 96)
        out.put32(edataRVA, at: directories)
        out.put32(UInt32(edata.count), at: directories + 4)
        out.put32(relocRVA, at: directories + 5 * 8)
        out.put32(UInt32(reloc.count), at: directories + 5 * 8 + 4)

        let sectionHeaders = directories + 128
        var raw = UInt32(headers)
        for (index, section) in sections.enumerated() {
            let header = sectionHeaders + index * 40
            for (offset, byte) in section.name.utf8.prefix(8).enumerated() { out[header + offset] = byte }
            let rawSize = align(UInt32(section.body.count), fileAlignment)
            out.put32(UInt32(section.body.count), at: header + 8)
            out.put32(section.rva, at: header + 12)
            out.put32(rawSize, at: header + 16)
            out.put32(raw, at: header + 20)
            out.put32(section.flags, at: header + 36)
            out.append(contentsOf: section.body)
            out.append(contentsOf: [UInt8](repeating: 0, count: Int(rawSize) - section.body.count))
            raw += rawSize
        }
        return Data(out)
    }

    private static func align(_ value: UInt32, _ alignment: UInt32) -> UInt32 {
        (value + alignment - 1) / alignment * alignment
    }

    static func latin1Less(_ a: String, _ b: String) -> Bool {
        Array(a.data(using: .isoLatin1) ?? Data(a.utf8)).lexicographicallyPrecedes(b.data(using: .isoLatin1) ?? Data(b.utf8))
    }
}

/// A PE file read just far enough for its export table.
struct PEImage {
    struct Section {
        let name: String
        let virtualAddress: UInt32
        let virtualSize: UInt32
        let rawOffset: UInt32
        let rawSize: UInt32
    }

    struct Export {
        let ordinal: UInt32
        let name: String?
        /// The forward string, when the export is a forward rather than code.
        let forward: String?
    }

    let bytes: [UInt8]
    let machine: UInt16
    let directories: [(rva: UInt32, size: UInt32)]
    let sections: [Section]

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        guard bytes.count >= 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A else { throw PEForwarderError.notPE }
        let pe = Int(try bytes.u32(at: 0x3C))
        guard bytes.count >= pe + 4, bytes[pe..<pe + 4].elementsEqual([0x50, 0x45, 0, 0]) else {
            throw PEForwarderError.notPE
        }
        machine = try bytes.u16(at: pe + 4)
        let sectionCount = Int(try bytes.u16(at: pe + 6))
        let optionalSize = Int(try bytes.u16(at: pe + 20))
        let opt = pe + 24
        let plus = try bytes.u16(at: opt) == 0x20B
        let directoryOffset = opt + (plus ? 112 : 96)
        let directoryCount = Int(try bytes.u32(at: opt + (plus ? 108 : 92)))
        guard directoryCount <= 16 else { throw PEForwarderError.truncated }
        directories = try (0..<directoryCount).map { i in
            (try bytes.u32(at: directoryOffset + i * 8), try bytes.u32(at: directoryOffset + i * 8 + 4))
        }
        sections = try (0..<sectionCount).map { i in
            let o = opt + optionalSize + i * 40
            guard o + 40 <= bytes.count else { throw PEForwarderError.truncated }
            let name = String(decoding: bytes[o..<o + 8].prefix { $0 != 0 }, as: UTF8.self)
            return Section(
                name: name, virtualAddress: try bytes.u32(at: o + 12), virtualSize: try bytes.u32(at: o + 8),
                rawOffset: try bytes.u32(at: o + 20), rawSize: try bytes.u32(at: o + 16))
        }
    }

    var arch: String {
        switch machine {
        case PEForwarder.x86_64: return "x86_64"
        case PEForwarder.i386: return "i386"
        default: return "0x" + String(machine, radix: 16)
        }
    }

    func offset(_ rva: UInt32) -> Int? {
        for s in sections where s.virtualAddress <= rva && UInt64(rva) < UInt64(s.virtualAddress) + UInt64(max(s.virtualSize, s.rawSize)) {
            let o = Int(rva - s.virtualAddress) + Int(s.rawOffset)
            if o < bytes.count { return o }
        }
        return nil
    }

    func cString(_ rva: UInt32) throws -> String {
        guard let start = offset(rva), let end = bytes[start...].firstIndex(of: 0) else {
            throw PEForwarderError.truncated
        }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// Every export with an address, in ordinal order. An address inside the export directory is a
    /// forward string, not code.
    func exports() throws -> [Export] {
        guard let (rva, size) = directories.first, rva != 0 else { return [] }
        guard let o = offset(rva) else { throw PEForwarderError.truncated }
        let base = try bytes.u32(at: o + 16)
        let functionCount = Int(try bytes.u32(at: o + 20))
        let nameCount = Int(try bytes.u32(at: o + 24))
        guard let functions = offset(try bytes.u32(at: o + 28)), let names = offset(try bytes.u32(at: o + 32)),
            let ordinals = offset(try bytes.u32(at: o + 36))
        else { throw PEForwarderError.truncated }
        var nameByIndex: [Int: String] = [:]
        for i in 0..<nameCount {
            nameByIndex[Int(try bytes.u16(at: ordinals + i * 2))] = try cString(try bytes.u32(at: names + i * 4))
        }
        var out: [Export] = []
        for i in 0..<functionCount {
            let address = try bytes.u32(at: functions + i * 4)
            guard address != 0 else { continue }
            let isForward = rva <= address && UInt64(address) < UInt64(rva) + UInt64(size)
            // A corrupt base near UInt32.max must be an error, not an overflow trap.
            let (ordinal, overflow) = base.addingReportingOverflow(UInt32(i))
            guard !overflow else { throw PEForwarderError.truncated }
            out.append(Export(
                ordinal: ordinal, name: nameByIndex[i], forward: isForward ? try cString(address) : nil))
        }
        return out
    }

    /// Export names in the order of the name pointer table ("" for one that cannot be read).
    func nameTable() throws -> [String] {
        guard let (rva, _) = directories.first, rva != 0 else { return [] }
        guard let o = offset(rva) else { throw PEForwarderError.truncated }
        guard let names = offset(try bytes.u32(at: o + 32)) else { throw PEForwarderError.truncated }
        return (0..<Int(try bytes.u32(at: o + 24))).map { i in
            (try? cString(bytes.u32(at: names + i * 4))) ?? ""
        }
    }
}

extension [UInt8] {
    func u16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw PEForwarderError.truncated }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { throw PEForwarderError.truncated }
        return (0..<4).reduce(0) { $0 | UInt32(self[offset + $1]) << (8 * $1) }
    }

    mutating func put16(_ value: UInt16, at offset: Int) {
        for i in 0..<2 { self[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }

    mutating func put32(_ value: UInt32, at offset: Int) {
        for i in 0..<4 { self[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }

    mutating func put64(_ value: UInt64, at offset: Int) {
        for i in 0..<8 { self[offset + i] = UInt8(truncatingIfNeeded: value >> (8 * i)) }
    }

    mutating func append16(_ value: UInt16) { append(contentsOf: [UInt8](repeating: 0, count: 2)); put16(value, at: count - 2) }
    mutating func append32(_ value: UInt32) { append(contentsOf: [UInt8](repeating: 0, count: 4)); put32(value, at: count - 4) }
}
