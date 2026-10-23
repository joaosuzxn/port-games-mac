import Foundation

public enum LauncherError: Error, LocalizedError, Equatable {
    case notInstalled(UInt32)
    /// Neither the recipe nor Steam's launch options name a Windows executable.
    case noExecutable(UInt32)
    /// The Mac's Steam did not open or log in in time; games would stop at "Steam must be running".
    case steamNotLoggedIn
    case alreadyRunning(UInt32)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let appID): return "app \(appID) is not installed (or its download did not finish)"
        case .noExecutable(let appID): return "no Windows executable is known for app \(appID); set one with the recipe"
        case .steamNotLoggedIn: return "Steam for Mac must be open and logged in to play; log in to Steam and try again"
        case .alreadyRunning(let appID): return "app \(appID) is already running"
        }
    }
}

/// A game started by the launcher.
public struct RunningGame: Sendable {
    let game: Process
    let runner: any WineRunning

    /// Waits for the game to end and returns its exit code. Wine (the Steam stub, services) keeps running
    /// until `stop()`.
    public func wait() async -> Int32 {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        game.terminationHandler = { _ in continuation.finish() }
        // It may have ended before the handler was set.
        if !game.isRunning { continuation.finish() }
        for await _ in stream {}
        return game.terminationStatus
    }

    /// Stops every Wine process of the game's prefix.
    public func stop() async throws {
        try await runner.stop(timeout: .seconds(30))
    }
}

/// Opens an installed game: the Mac's Steam logged in, the prefix ready, the bridge in place, the
/// Steam stub started, then the game from its folder on drive `G:`.
public struct GameLauncher: Sendable {
    private let paths: Paths
    private let engine: Engine
    private let steam: SteamClientProbe
    private let appInfo: @Sendable () throws -> [UInt32: AppInfo]
    private let preparePrefix: @Sendable (UInt32, Recipe, URL) async throws -> URL
    private let stageBridge: @Sendable (Engine, URL) async throws -> Void
    private let makeRunner: @Sendable (URL, URL) -> any WineRunning
    private let isPrefixRunning: @Sendable (URL) -> Bool
    private let loginTimeout: Duration
    private let pollInterval: Duration
    private let steamStubDelay: Duration

    static let steamStub = #"C:\Program Files (x86)\Steam\steam.exe"#

    /// `engine` must be installed (`EngineInstaller`) and the bridge published (`build_bridge.sh`).
    public init(
        paths: Paths, engine: Engine,
        appInfoURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/appcache/appinfo.vdf")
    ) {
        self.init(
            paths: paths, engine: engine, steam: SystemSteamClient(),
            appInfo: { try AppInfoReader.read(appInfoURL) },
            preparePrefix: { appID, recipe, gameDir in
                try await PrefixManager(paths: paths, engine: engine).ensurePrefix(appID: appID, recipe: recipe, gameDir: gameDir)
            },
            stageBridge: { engine, prefix in try Bridge(paths: paths, engineID: engine.id).stage(into: engine, prefix: prefix) },
            makeRunner: { prefix, log in WineRunner(engine: engine, prefix: prefix, log: log) },
            isPrefixRunning: { WineServerLock.holder(prefix: $0, serverRoot: WineServerLock.defaultRoot) != nil },
            loginTimeout: .seconds(60), pollInterval: .seconds(1), steamStubDelay: .seconds(2))
    }

    init(
        paths: Paths, engine: Engine, steam: SteamClientProbe,
        appInfo: @escaping @Sendable () throws -> [UInt32: AppInfo],
        preparePrefix: @escaping @Sendable (UInt32, Recipe, URL) async throws -> URL,
        stageBridge: @escaping @Sendable (Engine, URL) async throws -> Void,
        makeRunner: @escaping @Sendable (URL, URL) -> any WineRunning,
        isPrefixRunning: @escaping @Sendable (URL) -> Bool,
        loginTimeout: Duration, pollInterval: Duration, steamStubDelay: Duration
    ) {
        self.paths = paths
        self.engine = engine
        self.steam = steam
        self.appInfo = appInfo
        self.preparePrefix = preparePrefix
        self.stageBridge = stageBridge
        self.makeRunner = makeRunner
        self.isPrefixRunning = isPrefixRunning
        self.loginTimeout = loginTimeout
        self.pollInterval = pollInterval
        self.steamStubDelay = steamStubDelay
    }

    public func play(appID: UInt32) async throws -> RunningGame {
        // Everything that can fail without side effects first.
        guard let state = try GameStateStore.load(appID, paths: paths), state.complete else {
            throw LauncherError.notInstalled(appID)
        }
        let gameDir = URL(fileURLWithPath: state.installDir, isDirectory: true)
        let recipe = RecipeStore(paths: paths).recipe(for: appID)
        let (executable, arguments) = try launchCommand(appID: appID, recipe: recipe)
        let prefix = paths.prefix(appID)
        guard !isPrefixRunning(prefix) else { throw LauncherError.alreadyRunning(appID) }

        try await ensureSteam()
        let ready = try await preparePrefix(appID, recipe, gameDir)
        try await stageBridge(engine, ready)

        let runner = makeRunner(ready, paths.logs.appendingPathComponent("\(appID).log"))
        let env = WineEnvironment.make(engine: engine, prefix: ready, recipe: recipe, extra: Bridge.environment(appID: appID))
        // The stub tells games that Steam is running; give it a moment before the game asks.
        _ = try await runner.spawn([Self.steamStub], env: env, cwd: nil)
        try await Task.sleep(for: steamStubDelay)

        let parts = executable.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        let cwd = parts.dropLast().reduce(gameDir) { $0.appendingPathComponent($1, isDirectory: true) }
        let game = try await runner.spawn([#"G:\"# + parts.joined(separator: #"\"#)] + arguments, env: env, cwd: cwd)
        return RunningGame(game: game, runner: runner)
    }

    /// The recipe's executable (with its arguments), else Steam's first Windows launch option.
    private func launchCommand(appID: UInt32, recipe: Recipe) throws -> (String, [String]) {
        if let executable = recipe.executable { return (executable, recipe.arguments) }
        guard let launch = (try? appInfo())?[appID]?.windowsLaunch else { throw LauncherError.noExecutable(appID) }
        return (launch.executable, launch.arguments.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// Opens the Mac's Steam if needed and waits for its login, up to `loginTimeout`.
    private func ensureSteam() async throws {
        if !steam.isRunning() { try steam.open() }
        let deadline = ContinuousClock.now.advanced(by: loginTimeout)
        while !steam.isLoggedIn() {
            guard ContinuousClock.now < deadline else { throw LauncherError.steamNotLoggedIn }
            try await Task.sleep(for: pollInterval)
        }
    }
}
