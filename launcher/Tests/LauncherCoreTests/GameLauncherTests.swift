import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fakes

/// The Mac's Steam: closed or open, logged in after `loginAfterChecks` checks once opened.
private final class FakeSteam: SteamClientProbe, @unchecked Sendable {
    private let lock = NSLock()
    private var running: Bool
    private var checks = 0
    private let loginAfterChecks: Int?
    private(set) var opens = 0

    init(running: Bool, loginAfterChecks: Int?) {
        self.running = running
        self.loginAfterChecks = loginAfterChecks
    }

    func isRunning() -> Bool { lock.withLock { running } }
    func open() throws { lock.withLock { opens += 1; running = true } }
    func isLoggedIn() -> Bool {
        lock.withLock {
            guard running, let after = loginAfterChecks else { return false }
            checks += 1
            return checks > after
        }
    }
    var openCount: Int { lock.withLock { opens } }
}

/// Records what Wine would run; each spawn is a real short process so `RunningGame` has one to wait for.
private actor Calls {
    struct Spawn: Equatable {
        let args: [String]
        let cwd: String?
        let steamAppID: String?
        let prefix: String?
    }
    private(set) var spawns: [Spawn] = []
    private(set) var events: [String] = []
    private(set) var stops = 0

    func spawned(_ s: Spawn) { spawns.append(s); events.append("spawn \(s.args[0])") }
    func event(_ e: String) { events.append(e) }
    func stopped() { stops += 1 }
}

private struct FakeRunner: WineRunning {
    let calls: Calls
    let exitCode: Int32

    func run(_ args: [String], env: [String: String], cwd: URL?) async throws -> Int32 { 0 }

    func spawn(_ args: [String], env: [String: String], cwd: URL?) async throws -> Process {
        await calls.spawned(.init(args: args, cwd: cwd?.path, steamAppID: env["SteamAppId"], prefix: env["WINEPREFIX"]))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.1; exit \(exitCode)"]
        try process.run()
        return process
    }

    func stop(timeout: Duration) async throws { await calls.stopped() }
}

// MARK: - Fixtures

private let engine = Engine(id: "ws12-wine-sikarugir-11.0_1", root: URL(fileURLWithPath: "/E", isDirectory: true))

private func makePaths(in dir: URL) throws -> Paths {
    let paths = Paths(root: dir.appendingPathComponent("PortGames"), cache: dir.appendingPathComponent("Cache"))
    try paths.ensureCreated()
    return paths
}

private func installed(_ appID: UInt32, in paths: Paths, complete: Bool = true) throws -> URL {
    let dir = paths.gameDir(appID, library: nil)
    try GameStateStore.save(GameState(
        appID: appID, installDir: dir.path, buildID: 1, depotManifests: [:], installedAt: Date(), complete: complete),
        paths: paths)
    return dir
}

private func launcher(
    _ paths: Paths, steam: FakeSteam, calls: Calls, infos: [UInt32: AppInfo] = [:], exitCode: Int32 = 0,
    prefixRunning: Bool = false, timeout: Duration = .seconds(2)
) -> GameLauncher {
    GameLauncher(
        paths: paths, engine: engine, steam: steam,
        appInfo: { infos },
        preparePrefix: { appID, _, _ in
            await calls.event("prefix \(appID)")
            return paths.prefix(appID)
        },
        stageBridge: { _, _ in await calls.event("bridge") },
        makeRunner: { _, _ in FakeRunner(calls: calls, exitCode: exitCode) },
        isPrefixRunning: { _ in prefixRunning },
        loginTimeout: timeout, pollInterval: .milliseconds(10), steamStubDelay: .zero)
}

// MARK: - Tests

@Suite("GameLauncher")
struct GameLauncherTests {
    @Test func usesRecipeExecutable() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let gameDir = try installed(331160, in: paths)
            let calls = Calls()

            let game = try await launcher(paths, steam: FakeSteam(running: true, loginAfterChecks: 0), calls: calls)
                .play(appID: 331160)
            _ = await game.wait()

            let spawns = await calls.spawns
            #expect(spawns.map(\.args) == [[#"C:\Program Files (x86)\Steam\steam.exe"#], [#"G:\Cars.exe"#]])
            #expect(spawns.last?.cwd == gameDir.path)
            #expect(spawns.allSatisfy { $0.steamAppID == "331160" && $0.prefix == paths.prefix(331160).path })
            // Prefix and bridge are ready before anything starts.
            let events = await calls.events
            #expect(Array(events.prefix(2)).sorted() == ["bridge", "prefix 331160"])
        }
    }

    @Test func usesAppInfoLaunchWhenNoRecipe() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let gameDir = try installed(999, in: paths)
            let calls = Calls()
            let info = AppInfo(appID: 999, name: "Game", oslist: ["windows"],
                launch: [
                    LaunchEntry(executable: "Game.app", arguments: "", oslist: ["macos"]),
                    LaunchEntry(executable: "bin/Game.exe", arguments: "-foo  -bar", oslist: ["windows"]),
                ],
                publicBuildID: 1, depots: [])

            let game = try await launcher(paths, steam: FakeSteam(running: true, loginAfterChecks: 0), calls: calls,
                infos: [999: info]).play(appID: 999)
            _ = await game.wait()

            let last = try #require(await calls.spawns.last)
            #expect(last.args == [#"G:\bin\Game.exe"#, "-foo", "-bar"])
            #expect(last.cwd == gameDir.appendingPathComponent("bin").path)
        }
    }

    @Test func opensSteamWhenClosed() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            _ = try installed(331160, in: paths)
            let steam = FakeSteam(running: false, loginAfterChecks: 3)

            let game = try await launcher(paths, steam: steam, calls: Calls()).play(appID: 331160)
            _ = await game.wait()

            #expect(steam.openCount == 1)
        }
    }

    @Test func failsWhenNotLoggedInAfterTimeout() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            _ = try installed(331160, in: paths)
            let calls = Calls()
            let started = ContinuousClock.now

            await #expect(throws: LauncherError.steamNotLoggedIn) {
                try await launcher(paths, steam: FakeSteam(running: false, loginAfterChecks: nil), calls: calls,
                    timeout: .milliseconds(200)).play(appID: 331160)
            }
            #expect(ContinuousClock.now - started < .seconds(3))
            // Nothing was prepared or started.
            #expect(await calls.events.isEmpty)
        }
    }

    @Test func notInstalledIsError() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let steam = FakeSteam(running: true, loginAfterChecks: 0)
            await #expect(throws: LauncherError.notInstalled(331160)) {
                try await launcher(paths, steam: steam, calls: Calls()).play(appID: 331160)
            }
            // A download that did not finish is not installed either.
            _ = try installed(331160, in: paths, complete: false)
            await #expect(throws: LauncherError.notInstalled(331160)) {
                try await launcher(paths, steam: steam, calls: Calls()).play(appID: 331160)
            }
        }
    }

    @Test func noExecutableIsError() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            _ = try installed(999, in: paths)
            await #expect(throws: LauncherError.noExecutable(999)) {
                try await launcher(paths, steam: FakeSteam(running: true, loginAfterChecks: 0), calls: Calls())
                    .play(appID: 999)
            }
        }
    }

    /// Preparing the prefix stops its Wine: never do that to a game that is running.
    @Test func runningGameIsNotRestarted() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            _ = try installed(331160, in: paths)
            let calls = Calls()
            await #expect(throws: LauncherError.alreadyRunning(331160)) {
                try await launcher(paths, steam: FakeSteam(running: true, loginAfterChecks: 0), calls: calls,
                    prefixRunning: true).play(appID: 331160)
            }
            #expect(await calls.events.isEmpty)
        }
    }

    @Test func waitReturnsTheGamesExitCodeAndStopStopsWine() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            _ = try installed(331160, in: paths)
            let calls = Calls()

            let game = try await launcher(paths, steam: FakeSteam(running: true, loginAfterChecks: 0), calls: calls,
                exitCode: 3).play(appID: 331160)

            #expect(await game.wait() == 3)
            try await game.stop()
            #expect(await calls.stops == 1)
        }
    }
}
