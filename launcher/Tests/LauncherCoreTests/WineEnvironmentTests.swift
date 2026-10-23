import Darwin
import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fixtures

private struct FixtureError: Error, CustomStringConvertible {
    let description: String
}

private let engineID = "ws12-wine-sikarugir-11.0_1"

private func recipe(
    renderer: Renderer = .wined3d, environment: [String: String] = [:], dllOverrides: [String: String] = [:]
) -> Recipe {
    var recipe = Recipe.generic
    recipe.renderer = renderer
    recipe.environment = environment
    recipe.dllOverrides = dllOverrides
    return recipe
}

/// Builds the environment for an engine at `/E`, a prefix at `/P` and a home at `/H`.
private func environment(
    _ recipe: Recipe = recipe(), extra: [String: String] = [:]
) -> [String: String] {
    WineEnvironment.make(
        engine: Engine(id: engineID, root: URL(fileURLWithPath: "/E", isDirectory: true)),
        prefix: URL(fileURLWithPath: "/P", isDirectory: true),
        recipe: recipe, extra: extra,
        home: URL(fileURLWithPath: "/H", isDirectory: true))
}

private func write(_ text: String, to url: URL, executable: Bool = false) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    if executable {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private func read(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

/// Fake `wine`: prints what it got and exits with 7; `wine sleep` sleeps instead.
private let fakeWine = """
    #!/bin/sh
    if [ "$1" = "sleep" ]; then exec /bin/sleep 30; fi
    echo "args=$*"
    echo "prefix=$WINEPREFIX"
    echo "custom=$CUSTOM"
    echo "home=$HOME"
    echo "cwd=$(pwd -P)"
    echo "to stderr" >&2
    exit 7

    """

/// Fake `wineserver`: records each call in `<root>/wineserver.calls`. For `-k` it hangs if `<root>/hang`
/// exists (writing its PID to `<root>/hang.pid` first), and sends SIGTERM to the PID in `<root>/kill.pid`
/// if that exists (a `-k` that works).
private let fakeWineserver = """
    #!/bin/sh
    root="$(cd "$(dirname "$0")/../.." && pwd)"
    echo "$* WINEPREFIX=$WINEPREFIX" >> "$root/wineserver.calls"
    if [ "$1" = "-k" ]; then
      if [ -f "$root/hang" ]; then echo $$ > "$root/hang.pid"; exec /bin/sleep 30; fi
      if [ -f "$root/kill.pid" ]; then kill -TERM "$(cat "$root/kill.pid")"; fi
    fi
    exit 0

    """

/// Takes Wine's server lock the way `wineserver` does (fcntl write lock on byte 0 of the file given as
/// the only argument), then sleeps until a signal ends it.
private let lockHolderSource = """
    #include <fcntl.h>
    #include <unistd.h>
    int main(int argc, char **argv) {
        int fd = open(argv[1], O_CREAT | O_WRONLY, 0600);
        if (fd < 0) return 1;
        struct flock fl = { .l_start = 0, .l_len = 1, .l_type = F_WRLCK, .l_whence = SEEK_SET };
        if (fcntl(fd, F_SETLK, &fl) == -1) return 2;
        for (;;) pause();
    }

    """

/// An engine folder with the fake `wine` and `wineserver` scripts.
private func makeFakeEngine(in dir: URL) throws -> Engine {
    let engine = Engine(id: engineID, root: dir.appendingPathComponent("engine", isDirectory: true))
    try write(fakeWine, to: engine.wineBin, executable: true)
    try write(fakeWineserver, to: engine.wineserver, executable: true)
    return engine
}

/// Compiles the lock holder into `binary`. It must be a real Mach-O (not a script or a copied system
/// binary, which macOS kills) so that its executable path is where the test puts it.
private func compileLockHolder(to binary: URL) throws {
    let source = binary.deletingLastPathComponent().appendingPathComponent("lock-holder.c")
    try write(lockHolderSource, to: source)
    defer { try? FileManager.default.removeItem(at: source) }
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
    compiler.arguments = ["-o", binary.path, source.path]
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else {
        throw FixtureError(description: "cc failed with status \(compiler.terminationStatus)")
    }
}

/// Waits up to `limit` for `process` to end; true if it did.
private func waitForExit(_ process: Process, within limit: Duration) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: limit)
    while process.isRunning, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    return !process.isRunning
}

/// A fake wineserver for `prefix`: a lock holder at `binary` that owns the prefix's server lock.
/// Returns once the lock is visible, so `stop` sees a running server.
private func startServer(_ binary: URL, prefix: URL, serverRoot: URL) async throws -> Process {
    let lock = try #require(WineServerLock.lockFile(prefix: prefix, serverRoot: serverRoot))
    try FileManager.default.createDirectory(
        at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
    let server = Process()
    server.executableURL = binary
    server.arguments = [lock.path]
    try server.run()
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while WineServerLock.holder(prefix: prefix, serverRoot: serverRoot) != server.processIdentifier {
        guard ContinuousClock.now < deadline, server.isRunning else {
            server.terminate()
            throw FixtureError(description: "the fake wineserver did not take the lock")
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    return server
}

/// Everything a runner test needs: a fake engine, a prefix, a private server root and a log.
private struct RunnerFixture {
    let dir: URL
    let engine: Engine
    let prefix: URL
    let serverRoot: URL
    let log: URL
    let runner: WineRunner

    init(in dir: URL) throws {
        self.dir = dir
        engine = try makeFakeEngine(in: dir)
        prefix = dir.appendingPathComponent("prefix", isDirectory: true)
        serverRoot = dir.appendingPathComponent("server-root", isDirectory: true)
        log = dir.appendingPathComponent("logs/sub/game.log")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        runner = WineRunner(engine: engine, prefix: prefix, log: log, serverRoot: serverRoot)
    }

    var calls: String { read(engine.root.appendingPathComponent("wineserver.calls")) }
}

/// PIDs of the processes whose executable is inside `folder`.
private func processes(runningFrom folder: URL) -> [pid_t] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
    let count = pids.withUnsafeMutableBytes { buffer in
        proc_listallpids(buffer.baseAddress, Int32(buffer.count))
    }
    return pids.prefix(Int(max(count, 0))).filter { pid in
        pid > 0 && ProcessTable.executable(of: pid, isInside: folder)
    }
}

// MARK: - Environment

@Suite("WineEnvironment")
struct WineEnvironmentTests {
    /// Everything `wineskinlauncher` sets (capture of 2026-10-22), moved from the app bundle to the
    /// shared engine, with `WINEDEBUG=-all`.
    @Test func environmentKeys() {
        let expected: [String: String] = [
            "CX_APPLEGPTK_LIBD3DSHARED_PATH": "/E/renderer/d3dmetal/external/libd3dshared.dylib",
            "CX_APPLEGPT_LIBD3DSHARED_PATH": "/E/renderer/d3dmetal/external/libd3dshared.dylib",
            "CX_FWD_COMPAT_GL_CTX": "1",
            "CX_ROOT": "/E/wine",
            "DOTNET_EnableWriteXorExecute": "0",
            "DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN": "1",
            "DXVK_ASYNC": "1",
            "DXVK_SHADER_CACHE_PATH": "/H/.cache/dxvk",
            "DYLD_FALLBACK_LIBRARY_PATH":
                "/E/wine/lib:/E/wine/lib64:/E/Frameworks:/E/Frameworks/GStreamer.framework/Libraries"
                + ":/opt/wine/lib:/usr/lib:/usr/libexec:/usr/lib/system",
            "GST_PLUGIN_PATH": "/E/Frameworks/GStreamer.framework/Libraries/gstreamer-1.0",
            "MTL_HUD_ENABLED": "0",
            "MVK_CONFIG_FAST_MATH_ENABLED": "0",
            "MVK_CONFIG_RESUME_LOST_DEVICE": "1",
            "PATH": "/E/wine/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "QMLSCENE_DEVICE": "softwarecontext",
            "ROSETTA_ADVERTISE_AVX": "1",
            "SDL_JOYSTICK_MFI": "0",
            // Without it the Sikarugir Wine 11 build cannot start any Windows process.
            "SikarugirAppWine11": "1",
            "VK_DRIVER_FILES": "/E/Resources/vulkan/icd.d/kosmickrisp_mesa_icd.json",
            "WINEBOOT_HIDE_DIALOG": "1",
            "WINEDEBUG": "-all",
            "WINEDLLPATH": "/E/wine/lib/x86_64-windows:/E/wine/lib/i386-windows:/E/wine/lib/x86_64-unix",
            "WINEDLLPATH_CNCD": "/E/renderer/cnc_ddraw/wine",
            "WINEDLLPATH_DXMT": "/E/renderer/dxmt/wine",
            "WINEDLLPATH_PREPEND": "/E/renderer/dxmt/wine",
            "WINEMSYNC": "1",
            "WINEPREFIX": "/P",
        ]

        let env = environment()

        // Key by key first, so a failure names the variable; then the whole set (no extra keys,
        // and no WINEDLLOVERRIDES when the recipe has none).
        for (key, value) in expected {
            #expect(env[key] == value, "\(key)")
        }
        #expect(env == expected)
    }

    @Test(arguments: zip(
        [Renderer.wined3d, .d9vk, .dxvk, .d3dmetal],
        [
            // WineD3D gets Sikarugir's default, DXMT (Direct3D 10/11 over Metal); Carros ran with it.
            "/E/renderer/dxmt/wine", "/E/renderer/d9vk/wine", "/E/renderer/dxvk/wine",
            "/E/renderer/d3dmetal/wine",
        ]))
    func rendererPrepend(renderer: Renderer, folder: String) {
        #expect(environment(recipe(renderer: renderer))["WINEDLLPATH_PREPEND"] == folder)
    }

    @Test func dllOverridesSorted() {
        let env = environment(recipe(dllOverrides: ["dinput8": "n,b", "d3d9": "n", "ddraw": "b"]))
        #expect(env["WINEDLLOVERRIDES"] == "d3d9=n;ddraw=b;dinput8=n,b")
    }

    @Test func recipeEnvironmentWins() {
        let recipe = recipe(
            environment: ["WINEDEBUG": "+loaddll", "DXVK_HUD": "fps", "WINEDLLOVERRIDES": "from-recipe"],
            dllOverrides: ["d3d9": "n"])

        let withoutExtra = environment(recipe)
        #expect(withoutExtra["WINEDEBUG"] == "+loaddll")
        #expect(withoutExtra["DXVK_HUD"] == "fps")
        #expect(withoutExtra["WINEDLLOVERRIDES"] == "from-recipe")

        // `extra` (the Steam bridge, a run's own needs) goes last and beats the recipe.
        let withExtra = environment(recipe, extra: ["WINEDEBUG": "warn+all", "SteamAppId": "331160"])
        #expect(withExtra["WINEDEBUG"] == "warn+all")
        #expect(withExtra["SteamAppId"] == "331160")
        #expect(withExtra["DXVK_HUD"] == "fps")
    }

    @Test func defaultHomeIsTheUsersHome() {
        let env = WineEnvironment.make(
            engine: Engine(id: engineID, root: URL(fileURLWithPath: "/E")), prefix: URL(fileURLWithPath: "/P"),
            recipe: .generic)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(env["DXVK_SHADER_CACHE_PATH"] == home + "/.cache/dxvk")
    }
}

// MARK: - Runner

@Suite("WineRunner")
struct WineRunnerTests {
    @Test func serverDirectoryName() {
        // Same names Wine gave real servers on this Mac (/tmp/.wine-501/server-1000011-1809f2d).
        #expect(WineServerLock.directoryName(device: 0x100_0011, inode: 0x180_9f2d) == "server-1000011-1809f2d")
        #expect(WineServerLock.defaultRoot.path == "/tmp/.wine-\(getuid())")
    }

    @Test func runPassesArgumentsEnvironmentAndDirectory() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)
            let work = dir.appendingPathComponent("work", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let status = try await fixture.runner.run(
                ["wineboot", "-u"], env: ["WINEPREFIX": fixture.prefix.path, "CUSTOM": "x"], cwd: work)

            #expect(status == 7)
            let log = read(fixture.log)
            #expect(log.contains("wine wineboot -u"), "header line names the command")
            #expect(log.contains("args=wineboot -u"))
            #expect(log.contains("prefix=\(fixture.prefix.path)"))
            #expect(log.contains("custom=x"))
            // Variables not in `env` come from the launcher's own environment.
            #expect(log.contains("home=\(ProcessInfo.processInfo.environment["HOME"] ?? "")"))
            #expect(log.contains("cwd=\(try #require(ProcessTable.realPath(work.path)))"))
            #expect(log.contains("to stderr"))
        }
    }

    @Test func runAppendsToLog() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)

            _ = try await fixture.runner.run(["first"], env: [:], cwd: nil)
            _ = try await fixture.runner.run(["second"], env: [:], cwd: nil)

            let log = read(fixture.log)
            #expect(log.contains("args=first"))
            #expect(log.contains("args=second"))
        }
    }

    @Test func spawnReturnsRunningProcess() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)

            let process = try await fixture.runner.spawn(["sleep"], env: [:], cwd: nil)
            defer { if process.isRunning { process.terminate() } }

            #expect(process.isRunning)
            #expect(read(fixture.log).contains("wine sleep"))
            process.terminate()
            #expect(try await waitForExit(process, within: .seconds(5)))
        }
    }

    @Test func cancelledRunStopsTheProcess() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)
            let runner = fixture.runner

            let task = Task { try await runner.run(["sleep"], env: [:], cwd: nil) }
            try await Task.sleep(for: .milliseconds(300))
            let cancelled = ContinuousClock.now
            task.cancel()

            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(ContinuousClock.now - cancelled < .seconds(5))
        }
    }

    @Test func stopWithoutServerReturnsAtOnce() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)
            let started = ContinuousClock.now

            try await fixture.runner.stop(timeout: .seconds(20))

            #expect(ContinuousClock.now - started < .seconds(5))
            // `wineserver -k` ran with this prefix.
            #expect(fixture.calls.contains("-k WINEPREFIX=\(fixture.prefix.path)"))
        }
    }

    @Test func stopWaitsForServerToExit() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)
            let binary = fixture.engine.root.appendingPathComponent("wine/bin/fake-server")
            try compileLockHolder(to: binary)
            let server = try await startServer(binary, prefix: fixture.prefix, serverRoot: fixture.serverRoot)
            defer { if server.isRunning { server.terminate() } }
            try write("\(server.processIdentifier)", to: fixture.engine.root.appendingPathComponent("kill.pid"))
            let started = ContinuousClock.now

            try await fixture.runner.stop(timeout: .seconds(20))

            #expect(ContinuousClock.now - started < .seconds(10))
            #expect(try await waitForExit(server, within: .seconds(5)))
            // It went down by the SIGTERM of `wineserver -k`, not by the runner's SIGKILL.
            #expect(server.terminationReason == .uncaughtSignal)
            #expect(server.terminationStatus == SIGTERM)
        }
    }

    @Test func stopKillsServerAfterTimeout() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)
            let binary = fixture.engine.root.appendingPathComponent("wine/bin/fake-server")
            try compileLockHolder(to: binary)
            // No kill.pid: `wineserver -k` does nothing and the server keeps running.
            let server = try await startServer(binary, prefix: fixture.prefix, serverRoot: fixture.serverRoot)
            defer { if server.isRunning { server.terminate() } }

            try await fixture.runner.stop(timeout: .milliseconds(500))

            #expect(try await waitForExit(server, within: .seconds(5)))
            #expect(server.terminationStatus == SIGKILL)
            #expect(WineServerLock.holder(prefix: fixture.prefix, serverRoot: fixture.serverRoot) == nil)
            #expect(read(fixture.log).contains("SIGKILL"))
        }
    }

    @Test func stopDoesNotKillServerFromOutsideTheEngine() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)
            // Same program, same prefix, but its executable is not inside the engine folder.
            let binary = dir.appendingPathComponent("elsewhere/fake-server")
            try compileLockHolder(to: binary)
            let server = try await startServer(binary, prefix: fixture.prefix, serverRoot: fixture.serverRoot)
            defer { if server.isRunning { server.terminate() } }

            do {
                try await fixture.runner.stop(timeout: .milliseconds(300))
                Issue.record("expected an error")
            } catch let error as WineRunnerError {
                #expect(error == .foreignWineserver(prefix: fixture.prefix.path, pid: server.processIdentifier))
                #expect(error.localizedDescription.contains(fixture.prefix.path))
            }
            #expect(server.isRunning)
        }
    }

    @Test func stuckKillCommandDoesNotBlockStop() async throws {
        try await withAsyncScratchDirectory { dir in
            let fixture = try RunnerFixture(in: dir)
            let binary = fixture.engine.root.appendingPathComponent("wine/bin/fake-server")
            try compileLockHolder(to: binary)
            let server = try await startServer(binary, prefix: fixture.prefix, serverRoot: fixture.serverRoot)
            defer { if server.isRunning { server.terminate() } }
            try write("", to: fixture.engine.root.appendingPathComponent("hang"))
            let started = ContinuousClock.now

            try await fixture.runner.stop(timeout: .milliseconds(500))

            #expect(ContinuousClock.now - started < .seconds(5))
            #expect(try await waitForExit(server, within: .seconds(5)))
            // The stuck `wineserver -k` is not left behind either.
            let hung = try #require(pid_t(read(fixture.engine.root.appendingPathComponent("hang.pid"))
                .trimmingCharacters(in: .whitespacesAndNewlines)))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while kill(hung, 0) == 0, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(kill(hung, 0) == -1 && errno == ESRCH, "the stuck wineserver -k (PID \(hung)) is still there")
        }
    }
}

// MARK: - Integration (real engine, PORTGAMES_INTEGRATION=1)

private let integrationEnabled = ProcessInfo.processInfo.environment["PORTGAMES_INTEGRATION"] == "1"

@Suite("WineRunner integration", .enabled(if: integrationEnabled))
struct WineRunnerIntegrationTests {
    /// Installs the real engine from the local artifacts into a scratch root, creates a prefix with
    /// `wineboot -u` and stops Wine. No game and no window.
    @Test(.timeLimit(.minutes(10))) func integrationWineboot() async throws {
        let artifacts = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/portcarros/artefatos", isDirectory: true)
        try await withAsyncScratchDirectory { dir in
            let paths = Paths(
                root: dir.appendingPathComponent("PortGames", isDirectory: true),
                cache: dir.appendingPathComponent("Cache", isDirectory: true))
            try paths.ensureCreated()
            let engine = try EngineInstaller.install(
                template: artifacts.appendingPathComponent("Template-1.0.24.tar.xz"),
                engine: artifacts.appendingPathComponent("WS12WineSikarugir11.0_1.tar.xz"),
                id: engineID, paths: paths)
            let prefix = paths.prefix(331160)
            let log = paths.logs.appendingPathComponent("331160.log")
            let runner = WineRunner(engine: engine, prefix: prefix, log: log)
            let env = WineEnvironment.make(engine: engine, prefix: prefix, recipe: .generic)

            let started = ContinuousClock.now
            let status = try await runner.run(["wineboot", "-u"], env: env, cwd: nil)
            let booted = ContinuousClock.now
            try await runner.stop(timeout: .seconds(30))
            let stopped = ContinuousClock.now

            // Wine processes notice their server is gone right away; allow them a moment to exit.
            var left = processes(runningFrom: engine.root)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !left.isEmpty, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
                left = processes(runningFrom: engine.root)
            }
            print("integrationWineboot: wineboot \(booted - started) (status \(status)), stop \(stopped - booted)")
            print("integrationWineboot: processes left after stop: \(left)")

            let logText = read(log)
            #expect(status == 0, "wineboot -u failed; log tail:\n\(logText.suffix(4000))")
            #expect(FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path))
            #expect(WineServerLock.holder(prefix: prefix, serverRoot: WineServerLock.defaultRoot) == nil)
            #expect(left.isEmpty, "Wine processes still running: \(left)")
        }
    }
}
