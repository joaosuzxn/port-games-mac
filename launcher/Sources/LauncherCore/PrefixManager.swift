import Darwin
import Foundation

public enum PrefixError: Error, LocalizedError, Equatable {
    /// `wineboot -u` exited with `status` while creating the game's prefix.
    case creationFailed(appID: UInt32, status: Int32)
    /// A user folder of the prefix resolves outside it; nothing in it was changed.
    case outsidePrefix(path: String)
    /// A drive in `dosdevices/` is a real file or folder, not a link; it was left alone.
    case notALink(path: String)
    /// Another game runs: creating a prefix meanwhile can hang (bug #11), so it waits until that one ends.
    case otherGameRunning(UInt32)
    /// `wineboot -u` did not finish in time (Wine was stopped).
    case creationTimedOut(appID: UInt32)

    public var errorDescription: String? {
        switch self {
        case .creationFailed(let appID, let status):
            return "could not create the Wine prefix of app \(appID) (wineboot exited with \(status)); see its log"
        case .outsidePrefix(let path):
            return "\(path) points outside the Wine prefix; nothing was changed"
        case .notALink(let path):
            return "\(path) is not a link; it was left alone"
        case .otherGameRunning(let appID):
            return "app \(appID) is running; close it before the first start of another game (its Wine prefix is created then)"
        case .creationTimedOut(let appID):
            return "creating the Wine prefix of app \(appID) took too long and was stopped; close other Wine apps and try again"
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
    private let isPrefixRunning: @Sendable (URL) -> Bool
    private let winebootTimeout: Duration

    public init(paths: Paths, engine: Engine) {
        self.init(paths: paths, engine: engine) { prefix, log in
            WineRunner(engine: engine, prefix: prefix, log: log)
        }
    }

    init(
        paths: Paths, engine: Engine, makeRunner: @escaping @Sendable (URL, URL) -> any WineRunning,
        isPrefixRunning: @escaping @Sendable (URL) -> Bool = {
            WineServerLock.holder(prefix: $0, serverRoot: WineServerLock.defaultRoot) != nil
        },
        winebootTimeout: Duration = .seconds(180)
    ) {
        self.paths = paths
        self.engine = engine
        self.makeRunner = makeRunner
        self.isPrefixRunning = isPrefixRunning
        self.winebootTimeout = winebootTimeout
    }

    /// The game's prefix, created with `wineboot -u` if it has no registry yet, with Wine stopped and the
    /// recipe applied.
    ///
    /// Runs under the start lock (`prefixes/.create.lock`): no Wine of a launcher game starts while a prefix
    /// is being created (bug #11: creating one while another Wine starts hangs). The wait is bounded by
    /// the wineboot timeout. `GameLauncher` holds the same lock itself until the game is up.
    public func ensurePrefix(appID: UInt32, recipe: Recipe, gameDir: URL) async throws -> URL {
        let lock = try await FileLock.acquire(Self.startLock(paths))
        defer { lock.release() }
        return try await prepare(appID: appID, recipe: recipe, gameDir: gameDir)
    }

    /// The lock held from preparing a prefix until its game's Wine is up.
    static func startLock(_ paths: Paths) -> URL {
        paths.prefixes.appendingPathComponent(".create.lock")
    }

    /// `ensurePrefix` without taking the start lock: the caller holds it.
    func prepare(appID: UInt32, recipe: Recipe, gameDir: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: paths.prefixes, withIntermediateDirectories: true)
        let prefix = paths.prefix(appID)
        let runner = makeRunner(prefix, paths.logs.appendingPathComponent("\(appID).log"))
        if !isCreated(prefix) { try await create(prefix, appID: appID, recipe: recipe, runner: runner) }
        // wineserver writes the registry back when it exits: it must be down before the files are edited.
        try await runner.stop(timeout: .seconds(30))
        try applyRecipe(recipe, prefix: prefix, gameDir: gameDir)
        return prefix
    }

    private func isCreated(_ prefix: URL) -> Bool {
        FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path)
    }

    /// `wineboot -u` in a new prefix, refused while another game runs and stopped after `winebootTimeout`.
    private func create(_ prefix: URL, appID: UInt32, recipe: Recipe, runner: any WineRunning) async throws {
        let others = (try? FileManager.default.contentsOfDirectory(atPath: paths.prefixes.path)) ?? []
        for name in others.sorted() where !name.hasPrefix(".") && name != String(appID) {
            if let other = UInt32(name), isPrefixRunning(paths.prefixes.appendingPathComponent(name, isDirectory: true)) {
                throw PrefixError.otherGameRunning(other)
            }
        }
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let env = WineEnvironment.make(engine: engine, prefix: prefix, recipe: recipe)
        let timeout = winebootTimeout
        let started = ContinuousClock.now
        do {
            let status = try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask { try await runner.run(["wineboot", "-u"], env: env, cwd: nil) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    // Stop Wine before giving up: a wine client stuck on a wedged wineserver ignores the
                    // cancel, and the group waits for it; killing the server is what frees it.
                    try? await runner.stop(timeout: .seconds(30))
                    throw PrefixError.creationTimedOut(appID: appID)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            guard status == 0 else {
                // Ended by the timeout's stop, it is a timeout (the message that tells the user what happened).
                if ContinuousClock.now - started >= timeout { throw PrefixError.creationTimedOut(appID: appID) }
                throw PrefixError.creationFailed(appID: appID, status: status)
            }
        } catch {
            // wineboot's wineserver outlives it; it must be down before the lock is released (bug #11).
            // Detached, so that a cancelled caller does not cancel the stop as well.
            await Task.detached { try? await runner.stop(timeout: .seconds(30)) }.value
            throw error
        }
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
