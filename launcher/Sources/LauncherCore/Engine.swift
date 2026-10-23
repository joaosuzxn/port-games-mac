import Foundation

/// An installed Wine engine: the Wine build plus the frameworks and graphics layers it needs.
///
/// One engine is installed once (`engines/<id>/`) and shared by every game's prefix.
/// ```
/// <root>/wine/bin/{wine,wineserver}   Wine itself (from the engine archive)
/// <root>/Frameworks/                  libraries Wine loads (from the template)
/// <root>/renderer/{d9vk,dxvk,d3dmetal,…}  graphics layers (from the template)
/// ```
public struct Engine: Sendable, Equatable {
    public let id: String
    public let root: URL

    public init(id: String, root: URL) {
        self.id = id
        self.root = root
    }

    public var wineBin: URL { root.appendingPathComponent("wine/bin/wine", isDirectory: false) }
    public var wineserver: URL { root.appendingPathComponent("wine/bin/wineserver", isDirectory: false) }
    public var frameworks: URL { root.appendingPathComponent("Frameworks", isDirectory: true) }

    /// Folder with the files of a graphics layer, or `nil` for `.wined3d` (built into Wine).
    ///
    /// For `.d9vk` and `.dxvk` it is the `wine/` folder with the replacement DLLs. For `.d3dmetal` it is
    /// the layer's own folder, because it holds `external/` (D3DMetal.framework) next to `wine/`.
    public func rendererDir(_ renderer: Renderer) -> URL? {
        let renderers = root.appendingPathComponent("renderer", isDirectory: true)
        switch renderer {
        case .wined3d: return nil
        case .d9vk: return renderers.appendingPathComponent("d9vk/wine", isDirectory: true)
        case .dxvk: return renderers.appendingPathComponent("dxvk/wine", isDirectory: true)
        case .d3dmetal: return renderers.appendingPathComponent("d3dmetal", isDirectory: true)
        }
    }
}

public enum EngineError: Error, LocalizedError, Equatable {
    /// `tar` failed on the archive (corrupted, truncated or missing); `output` is what it printed.
    case extractionFailed(archive: String, status: Int32, output: String)
    /// The archive extracted, but does not have the folders the engine needs.
    case unexpectedLayout(archive: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .extractionFailed(let archive, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "could not extract \(archive) (tar status \(status))" + (detail.isEmpty ? "" : ": \(detail)")
        case .unexpectedLayout(let archive, let detail):
            return "\(archive) does not have the expected layout: \(detail)"
        }
    }
}

/// Installs the shared engine from the two downloaded archives. Not safe to call concurrently.
public enum EngineInstaller {
    /// The engine with this ID if it is fully installed, else `nil`.
    public static func installed(id: String, paths: Paths) -> Engine? {
        let engine = Engine(id: id, root: paths.engines.appendingPathComponent(id, isDirectory: true))
        let fileManager = FileManager.default
        let pieces = [engine.wineBin, engine.frameworks, engine.root.appendingPathComponent("renderer")]
        return pieces.allSatisfy { fileManager.fileExists(atPath: $0.path) } ? engine : nil
    }

    /// Installs into `<paths.engines>/<id>`, or returns the engine untouched when it is already there.
    ///
    /// Both archives are extracted with the system `tar` (it keeps the frameworks' symbolic links) and
    /// assembled in a hidden `.installing-*` folder next to the final one. That folder replaces
    /// `<id>` by rename only when everything is in place, so a failure at any point leaves
    /// what was there before (and no `.installing-*` folder) behind.
    ///
    /// - Parameters:
    ///   - template: the Sikarugir template archive (`Template-*.tar.xz`).
    ///   - engine: the Wine engine archive (`WS12Wine…tar.xz`).
    public static func install(template: URL, engine: URL, id: String, paths: Paths) throws -> Engine {
        if let existing = installed(id: id, paths: paths) { return existing }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.engines, withIntermediateDirectories: true)
        let staging = paths.engines.appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        // Also runs after success, when `assembled` has already been renamed out and only scratch is left.
        defer { try? fileManager.removeItem(at: staging) }

        let work = staging.appendingPathComponent("work", isDirectory: true)
        let assembled = staging.appendingPathComponent("engine", isDirectory: true)
        try fileManager.createDirectory(at: assembled, withIntermediateDirectories: false)

        let templateApp = try extract(template, into: work.appendingPathComponent("template", isDirectory: true))
        let wineBundle = try extract(engine, into: work.appendingPathComponent("engine", isDirectory: true))

        let frameworks = templateApp.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let renderer = templateApp.appendingPathComponent("Contents/SharedSupport/renderer", isDirectory: true)
        for (folder, name) in [(frameworks, "Contents/Frameworks"), (renderer, "Contents/SharedSupport/renderer")] {
            try require(directory: folder, named: name, in: template)
        }
        guard fileManager.fileExists(atPath: wineBundle.appendingPathComponent("bin/wine").path) else {
            throw EngineError.unexpectedLayout(archive: engine.lastPathComponent, detail: "missing bin/wine")
        }

        try fileManager.moveItem(at: wineBundle, to: assembled.appendingPathComponent("wine", isDirectory: true))
        try fileManager.moveItem(at: frameworks, to: assembled.appendingPathComponent("Frameworks", isDirectory: true))
        try fileManager.moveItem(at: renderer, to: assembled.appendingPathComponent("renderer", isDirectory: true))

        let root = paths.engines.appendingPathComponent(id, isDirectory: true)
        try replace(root, with: assembled)
        return Engine(id: id, root: root)
    }

    /// Extracts `archive` into `folder` and returns its single top-level item.
    private static func extract(_ archive: URL, into folder: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xJf", archive.path, "-C", folder.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Read before waiting: a full pipe would block tar and the wait would never end.
        let output = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EngineError.extractionFailed(
                archive: archive.lastPathComponent, status: process.terminationStatus,
                output: String(decoding: output, as: UTF8.self))
        }

        // Hidden entries (macOS `._*` metadata) are not the archive's content.
        let roots = try fileManager.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }
        guard roots.count == 1 else {
            throw EngineError.unexpectedLayout(
                archive: archive.lastPathComponent,
                detail: "expected a single root folder, found \(roots.sorted())")
        }
        return folder.appendingPathComponent(roots[0], isDirectory: true)
    }

    private static func require(directory: URL, named name: String, in archive: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw EngineError.unexpectedLayout(archive: archive.lastPathComponent, detail: "missing \(name)")
        }
    }

    /// Puts `new` in place of `final` by rename (same volume). Whatever was at `final` (an incomplete
    /// install) is deleted only after `new` is in place, and put back if the rename fails.
    private static func replace(_ final: URL, with new: URL) throws {
        let fileManager = FileManager.default
        var displaced: URL?
        if (try? fileManager.attributesOfItem(atPath: final.path)) != nil {
            let aside = final.deletingLastPathComponent()
                .appendingPathComponent(".replaced-\(UUID().uuidString)", isDirectory: true)
            try fileManager.moveItem(at: final, to: aside)
            displaced = aside
        }
        do {
            try fileManager.moveItem(at: new, to: final)
        } catch {
            if let displaced { try? fileManager.moveItem(at: displaced, to: final) }
            throw error
        }
        if let displaced { try? fileManager.removeItem(at: displaced) }
    }
}
