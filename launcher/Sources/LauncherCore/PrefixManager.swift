import Darwin
import Foundation

public enum PrefixError: Error, LocalizedError, Equatable {
    /// `wineboot -u` exited with `status` while creating the game's prefix.
    case creationFailed(appID: UInt32, status: Int32)
    /// A user folder of the prefix resolves outside it; nothing in it was changed.
    case outsidePrefix(path: String)
    /// A drive in `dosdevices/` is a real file or folder, not a link; it was left alone.
    case notALink(path: String)

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let appID, let status):
            return "could not create the Wine prefix of app \(appID) (wineboot exited with \(status)); see its log"
        case .outsidePrefix(let path):
            return "\(path) points outside the Wine prefix; nothing was changed"
        case .notALink(let path):
            return "\(path) is not a link; it was left alone"
        }
    }
}

/// One Wine prefix per game (`prefixes/<appID>`), always on the internal disk. The game's files stay
/// where they were installed and are reached through drive links.
public struct PrefixManager: Sendable {
    public let paths: Paths
    public let engine: Engine
    /// Builds the runner for a prefix and its log; tests put a fake here.
    private let makeRunner: @Sendable (_ prefix: URL, _ log: URL) -> any WineRunning

    public init(paths: Paths, engine: Engine) {
        self.init(paths: paths, engine: engine) { prefix, log in
            WineRunner(engine: engine, prefix: prefix, log: log)
        }
    }

    init(paths: Paths, engine: Engine, makeRunner: @escaping @Sendable (URL, URL) -> any WineRunning) {
        self.paths = paths
        self.engine = engine
        self.makeRunner = makeRunner
    }

    /// The game's prefix, created with `wineboot -u` if it has no registry yet, with Wine stopped and the
    /// recipe applied.
    ///
    /// Runs under an exclusive lock on `prefixes/.create.lock`, so two prefixes are never created at once
    /// (bug #11: creating one while another Wine starts hangs).
    public func ensurePrefix(appID: UInt32, recipe: Recipe, gameDir: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: paths.prefixes, withIntermediateDirectories: true)
        let lock = try await CreationLock.acquire(paths.prefixes.appendingPathComponent(".create.lock"))
        defer { lock.release() }

        let prefix = paths.prefix(appID)
        let runner = makeRunner(prefix, paths.logs.appendingPathComponent("\(appID).log"))
        if !FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) {
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
            let env = WineEnvironment.make(engine: engine, prefix: prefix, recipe: recipe)
            do {
                let status = try await runner.run(["wineboot", "-u"], env: env, cwd: nil)
                guard status == 0 else { throw PrefixError.creationFailed(appID: appID, status: status) }
            } catch {
                // wineboot's wineserver outlives it; it must be down before the lock is released (bug #11).
                // Detached, so that a cancelled caller does not cancel the stop as well.
                await Task.detached { try? await runner.stop(timeout: .seconds(30)) }.value
                throw error
            }
        }
        // wineserver writes the registry back when it exits: it must be down before the files are edited.
        try await runner.stop(timeout: .seconds(30))
        try applyRecipe(recipe, prefix: prefix, gameDir: gameDir)
        return prefix
    }

    /// Writes the recipe into a prefix. **The prefix's Wine must be stopped.**
    ///
    /// - Registry keys of the recipe, plus `X11 Driver\EmulateModeset` (`"y"` or `"n"`).
    /// - Drive `G:` → `gameDir`. With a CD label, drive `D:` → `gameDir` too, as a CD-ROM with that
    ///   label (`.windows-label` in `gameDir`), for games that check their disc.
    /// - Each user's `Documents` becomes a real folder inside the prefix instead of Wine's link to the
    ///   Mac's Documents, so saves stay with the game and on the internal disk.
    public func applyRecipe(_ recipe: Recipe, prefix: URL, gameDir: URL) throws {
        let documents = try userDocuments(in: prefix)

        var keys = recipe.registry
        keys.append(RegistryKey(
            hive: .user, key: #"Software\Wine\X11 Driver"#,
            values: ["EmulateModeset": .string(recipe.emulateModeset ? "y" : "n")]))
        if recipe.cdLabel != nil {
            keys.append(RegistryKey(hive: .system, key: #"Software\Wine\Drives"#, values: ["d:": .string("cdrom")]))
        }
        try RegistryFile.apply(keys, prefix: prefix)

        let fileManager = FileManager.default
        let dosdevices = prefix.appendingPathComponent("dosdevices", isDirectory: true)
        try fileManager.createDirectory(at: dosdevices, withIntermediateDirectories: true)
        try link(dosdevices.appendingPathComponent("g:"), to: gameDir)
        let cdDrive = dosdevices.appendingPathComponent("d:")
        if let label = recipe.cdLabel {
            try link(cdDrive, to: gameDir)
            try fileManager.createDirectory(at: gameDir, withIntermediateDirectories: true)
            try Data((label + "\n").utf8).write(to: gameDir.appendingPathComponent(".windows-label"))
        } else if (try? fileManager.destinationOfSymbolicLink(atPath: cdDrive.path)) == gameDir.path {
            try fileManager.removeItem(at: cdDrive)
        }

        for folder in documents {
            if isSymlink(folder) { try fileManager.removeItem(at: folder) }  // only the link, never its target
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    /// The `Documents` of every user folder (not `Public`), after checking that each user folder is
    /// really inside the prefix. Checked before anything is changed.
    private func userDocuments(in prefix: URL) throws -> [URL] {
        let users = prefix.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: users.path) else { return [] }
        guard let root = ProcessTable.realPath(prefix.path) else { return [] }
        var documents: [URL] = []
        for name in names.sorted() where name != "Public" && !name.hasPrefix(".") {
            let user = users.appendingPathComponent(name, isDirectory: true)
            guard let real = ProcessTable.realPath(user.path), real.hasPrefix(root + "/") else {
                throw PrefixError.outsidePrefix(path: user.path)
            }
            documents.append(user.appendingPathComponent("Documents", isDirectory: true))
        }
        return documents
    }

    /// Points the link `drive` at `target`, replacing an older link (never a real file or folder).
    private func link(_ drive: URL, to target: URL) throws {
        let fileManager = FileManager.default
        if isSymlink(drive) {
            try fileManager.removeItem(at: drive)
        } else if fileManager.fileExists(atPath: drive.path) {
            throw PrefixError.notALink(path: drive.path)
        }
        try fileManager.createSymbolicLink(atPath: drive.path, withDestinationPath: target.path)
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }
}

/// An exclusive `flock` on a file, taken without blocking a thread: it polls until free.
private struct CreationLock {
    let fd: Int32

    static func acquire(_ file: URL) async throws -> CreationLock {
        let fd = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path]) }
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                close(fd)
                throw error
            }
        }
        return CreationLock(fd: fd)
    }

    /// Closing the descriptor releases the lock.
    func release() { close(fd) }
}
