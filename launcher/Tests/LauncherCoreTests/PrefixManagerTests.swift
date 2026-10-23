import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fixtures

private let engine = Engine(id: "ws12-wine-sikarugir-11.0_1", root: URL(fileURLWithPath: "/E", isDirectory: true))

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func read(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

private func linkTarget(_ url: URL) -> String? {
    try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
}

private func isSymlink(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
}

private func makePaths(in dir: URL) throws -> Paths {
    let paths = Paths(
        root: dir.appendingPathComponent("PortGames", isDirectory: true),
        cache: dir.appendingPathComponent("Cache", isDirectory: true))
    try paths.ensureCreated()
    return paths
}

/// A prefix the way a fresh `wineboot` on macOS leaves it: registry files, `dosdevices/` and a
/// `Documents` that is a link to the Mac's own Documents (here a folder outside the prefix).
private func makeFakePrefix(_ prefix: URL, outsideDocuments: URL) throws {
    try write("WINE REGISTRY Version 2\n;; All keys relative to \\\\Machine\n\n#arch=win64\n",
        to: prefix.appendingPathComponent("system.reg"))
    try write("WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n#arch=win64\n",
        to: prefix.appendingPathComponent("user.reg"))
    let fileManager = FileManager.default
    try fileManager.createDirectory(
        at: prefix.appendingPathComponent("dosdevices", isDirectory: true), withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(
        atPath: prefix.appendingPathComponent("dosdevices/c:").path, withDestinationPath: "../drive_c")
    let user = prefix.appendingPathComponent("drive_c/users/u", isDirectory: true)
    try fileManager.createDirectory(at: user, withIntermediateDirectories: true)
    try write("keep me", to: outsideDocuments.appendingPathComponent("mine.txt"))
    try fileManager.createSymbolicLink(
        at: user.appendingPathComponent("Documents"), withDestinationURL: outsideDocuments)
}

private func carros(in paths: Paths) -> Recipe {
    RecipeStore(paths: paths).recipe(for: 331160)
}

/// Records what the fake runners do, across prefixes.
private actor Recorder {
    private(set) var runs: [(prefix: String, args: [String])] = []
    private(set) var stops: [String] = []
    private var active = 0
    private(set) var maxActive = 0

    func begin(_ prefix: URL, _ args: [String]) {
        runs.append((prefix.path, args))
        active += 1
        maxActive = max(maxActive, active)
    }

    func end() { active -= 1 }
    func stopped(_ prefix: URL) { stops.append(prefix.path) }
}

/// Stands in for `WineRunner`: `wineboot` writes the registry files (slowly, so overlaps would show)
/// and exits with `status`.
private struct FakeRunner: WineRunning {
    let prefix: URL
    let recorder: Recorder
    var status: Int32 = 0
    var error: CancellationError?
    /// wineboot that never ends (bug #11), until cancelled.
    var hangs = false
    /// wineboot that ignores cancellation (a wine client stuck on a wedged wineserver) until `stop`.
    var hangsUntilStop = false

    func run(_ args: [String], env: [String: String], cwd: URL?) async throws -> Int32 {
        await recorder.begin(prefix, args)
        if let error {
            await recorder.end()
            throw error
        }
        if hangs {
            defer { Task { await recorder.end() } }
            try await Task.sleep(for: .seconds(60))
        }
        if hangsUntilStop {
            while await recorder.stops.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
            await recorder.end()
            return 1
        }
        try await Task.sleep(for: .milliseconds(150))
        if status == 0 {
            try makeFakePrefix(prefix, outsideDocuments: prefix.deletingLastPathComponent()
                .appendingPathComponent("mac-docs-\(prefix.lastPathComponent)", isDirectory: true))
        }
        await recorder.end()
        return status
    }

    func spawn(_ args: [String], env: [String: String], cwd: URL?) async throws -> Process {
        Issue.record("spawn is not used to create a prefix")
        return Process()
    }

    func stop(timeout: Duration) async throws { await recorder.stopped(prefix) }
}

private func manager(_ paths: Paths, _ recorder: Recorder, status: Int32 = 0) -> PrefixManager {
    PrefixManager(paths: paths, engine: engine) { prefix, _ in
        FakeRunner(prefix: prefix, recorder: recorder, status: status)
    }
}

// MARK: - Tests

@Suite("PrefixManager")
struct PrefixManagerTests {
    @Test func appliesCarros() throws {
        try withScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let prefix = paths.prefix(331160)
            let gameDir = dir.appendingPathComponent("Games/331160", isDirectory: true)
            try makeFakePrefix(prefix, outsideDocuments: dir.appendingPathComponent("MacDocuments"))

            try PrefixManager(paths: paths, engine: engine).applyRecipe(carros(in: paths), prefix: prefix, gameDir: gameDir)

            // G: is the game folder; D: is the same folder as a CD labelled DISC2 (the game's disc check).
            #expect(linkTarget(prefix.appendingPathComponent("dosdevices/g:")) == gameDir.path)
            #expect(linkTarget(prefix.appendingPathComponent("dosdevices/d:")) == gameDir.path)
            #expect(linkTarget(prefix.appendingPathComponent("dosdevices/c:")) == "../drive_c")
            #expect(read(gameDir.appendingPathComponent(".windows-label")) == "DISC2\n")

            let system = read(prefix.appendingPathComponent("system.reg"))
            #expect(system.contains(#"[Software\\Wine\\Drives]"#))
            #expect(system.contains(#""d:"="cdrom""#))
            #expect(system.contains(#""Enable SDL"=dword:00000001"#))
            let user = read(prefix.appendingPathComponent("user.reg"))
            #expect(user.contains(#"[Software\\Wine\\X11 Driver]"#))
            #expect(user.contains(#""EmulateModeset"="y""#))
            #expect(user.contains(#""Resolution"=dword:0000000e"#))
            #expect(user.contains(#""MultiSampleType"=dword:00000004"#))
            #expect(user.contains(#""FullscreenEffects"=dword:00000001"#))
        }
    }

    @Test func emulateModesetOffAndNoCD() throws {
        try withScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let prefix = paths.prefix(480)
            let gameDir = dir.appendingPathComponent("Games/480", isDirectory: true)
            try makeFakePrefix(prefix, outsideDocuments: dir.appendingPathComponent("MacDocuments"))
            var recipe = Recipe.generic
            recipe.emulateModeset = false

            try PrefixManager(paths: paths, engine: engine).applyRecipe(recipe, prefix: prefix, gameDir: gameDir)

            #expect(read(prefix.appendingPathComponent("user.reg")).contains(#""EmulateModeset"="n""#))
            #expect(linkTarget(prefix.appendingPathComponent("dosdevices/g:")) == gameDir.path)
            #expect(linkTarget(prefix.appendingPathComponent("dosdevices/d:")) == nil)
            #expect(!FileManager.default.fileExists(atPath: gameDir.appendingPathComponent(".windows-label").path))
        }
    }

    @Test func reapplyingIsIdempotent() throws {
        try withScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let prefix = paths.prefix(331160)
            let gameDir = dir.appendingPathComponent("Games/331160", isDirectory: true)
            try makeFakePrefix(prefix, outsideDocuments: dir.appendingPathComponent("MacDocuments"))
            let manager = PrefixManager(paths: paths, engine: engine)

            try manager.applyRecipe(carros(in: paths), prefix: prefix, gameDir: gameDir)
            let first = read(prefix.appendingPathComponent("user.reg"))
            try manager.applyRecipe(carros(in: paths), prefix: prefix, gameDir: gameDir)

            #expect(read(prefix.appendingPathComponent("user.reg")) == first)
            #expect(linkTarget(prefix.appendingPathComponent("dosdevices/d:")) == gameDir.path)
        }
    }

    @Test func documentsBecomesRealDir() throws {
        try withScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let prefix = paths.prefix(331160)
            let outside = dir.appendingPathComponent("MacDocuments", isDirectory: true)
            try makeFakePrefix(prefix, outsideDocuments: outside)
            let documents = prefix.appendingPathComponent("drive_c/users/u/Documents", isDirectory: true)

            try PrefixManager(paths: paths, engine: engine)
                .applyRecipe(.generic, prefix: prefix, gameDir: dir.appendingPathComponent("Games/1"))

            // Saves now land inside the prefix (internal disk), not in the Mac's Documents.
            var isDirectory: ObjCBool = false
            #expect(!isSymlink(documents))
            #expect(FileManager.default.fileExists(atPath: documents.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            // Only the link went away; what it pointed to is untouched.
            #expect(read(outside.appendingPathComponent("mine.txt")) == "keep me")
        }
    }

    @Test func userFolderOutsidePrefixIsRefused() throws {
        try withScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let prefix = paths.prefix(331160)
            let outside = dir.appendingPathComponent("MacDocuments", isDirectory: true)
            try makeFakePrefix(prefix, outsideDocuments: outside)
            // A whole user folder that is a link out of the prefix: its Documents is not ours to change.
            let elsewhere = dir.appendingPathComponent("elsewhere-user", isDirectory: true)
            try FileManager.default.createDirectory(
                at: elsewhere.appendingPathComponent("Documents"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: prefix.appendingPathComponent("drive_c/users/v"), withDestinationURL: elsewhere)

            #expect(throws: PrefixError.self) {
                try PrefixManager(paths: paths, engine: engine)
                    .applyRecipe(.generic, prefix: prefix, gameDir: dir.appendingPathComponent("Games/1"))
            }
            #expect(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("Documents").path))
        }
    }

    @Test func createsStopsAndApplies() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let recorder = Recorder()
            let gameDir = dir.appendingPathComponent("Games/331160", isDirectory: true)

            let prefix = try await manager(paths, recorder)
                .ensurePrefix(appID: 331160, recipe: carros(in: paths), gameDir: gameDir)

            #expect(prefix == paths.prefix(331160))
            #expect(await recorder.runs.map(\.args) == [["wineboot", "-u"]])
            #expect(await recorder.stops == [prefix.path])
            #expect(read(prefix.appendingPathComponent("user.reg")).contains(#""EmulateModeset"="y""#))
            #expect(linkTarget(prefix.appendingPathComponent("dosdevices/g:")) == gameDir.path)
        }
    }

    @Test func existingPrefixIsNotRecreated() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let recorder = Recorder()
            let prefix = paths.prefix(331160)
            try makeFakePrefix(prefix, outsideDocuments: dir.appendingPathComponent("MacDocuments"))

            _ = try await manager(paths, recorder)
                .ensurePrefix(appID: 331160, recipe: carros(in: paths), gameDir: dir.appendingPathComponent("G"))

            #expect(await recorder.runs.isEmpty)
            // Wine is still stopped before the registry is edited.
            #expect(await recorder.stops == [prefix.path])
            #expect(read(prefix.appendingPathComponent("user.reg")).contains(#""EmulateModeset"="y""#))
        }
    }

    @Test func failedWinebootIsAnError() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let recorder = Recorder()

            await #expect(throws: PrefixError.creationFailed(appID: 331160, status: 1)) {
                try await manager(paths, recorder, status: 1)
                    .ensurePrefix(appID: 331160, recipe: carros(in: paths), gameDir: dir.appendingPathComponent("G"))
            }
            // Its Wine is stopped, and a later call tries again (no system.reg, so not "created").
            #expect(await recorder.stops == [paths.prefix(331160).path])
            _ = try? await manager(paths, recorder, status: 1)
                .ensurePrefix(appID: 331160, recipe: carros(in: paths), gameDir: dir.appendingPathComponent("G"))
            #expect(await recorder.runs.count == 2)
        }
    }

    @Test func throwingWinebootStillStopsWine() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let recorder = Recorder()
            let manager = PrefixManager(paths: paths, engine: engine) { prefix, _ in
                FakeRunner(prefix: prefix, recorder: recorder, error: CancellationError())
            }

            await #expect(throws: CancellationError.self) {
                try await manager.ensurePrefix(appID: 331160, recipe: .generic, gameDir: dir.appendingPathComponent("G"))
            }
            // The wineserver wineboot started must be down before the creation lock is released.
            #expect(await recorder.stops == [paths.prefix(331160).path])
        }
    }

    /// A game whose prefix exists does not wait behind another game's (possibly hung) creation.
    @Test func existingPrefixSkipsTheCreationLock() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            try makeFakePrefix(paths.prefix(331160), outsideDocuments: dir.appendingPathComponent("MacDocuments"))
            let lock = try await FileLock.acquire(paths.prefixes.appendingPathComponent(".create.lock"))
            defer { lock.release() }

            let done = Task { try await manager(paths, Recorder()).ensurePrefix(
                appID: 331160, recipe: .generic, gameDir: dir.appendingPathComponent("G")) }
            try await Task.sleep(for: .seconds(1))
            let finished = ContinuousClock.now
            _ = try await done.value
            #expect(ContinuousClock.now - finished < .milliseconds(200), "waited for the creation lock")
        }
    }

    /// Spec (bug #11): no prefix is created while a game runs; it says so instead of hanging.
    @Test func noCreationWhileAnotherGameRuns() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            try FileManager.default.createDirectory(at: paths.prefix(480), withIntermediateDirectories: true)
            let recorder = Recorder()
            let manager = PrefixManager(paths: paths, engine: engine,
                makeRunner: { prefix, _ in FakeRunner(prefix: prefix, recorder: recorder) },
                isPrefixRunning: { $0.lastPathComponent == "480" })

            await #expect(throws: PrefixError.otherGameRunning(480)) {
                try await manager.ensurePrefix(appID: 331160, recipe: .generic, gameDir: dir.appendingPathComponent("G"))
            }
            #expect(await recorder.runs.isEmpty)
        }
    }

    @Test func hungWinebootTimesOut() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let recorder = Recorder()
            let manager = PrefixManager(paths: paths, engine: engine,
                makeRunner: { prefix, _ in FakeRunner(prefix: prefix, recorder: recorder, hangs: true) },
                winebootTimeout: .milliseconds(300))
            let started = ContinuousClock.now

            await #expect(throws: PrefixError.creationTimedOut(appID: 331160)) {
                try await manager.ensurePrefix(appID: 331160, recipe: .generic, gameDir: dir.appendingPathComponent("G"))
            }
            #expect(ContinuousClock.now - started < .seconds(5))
            let stops = await recorder.stops
            #expect(!stops.isEmpty && stops.allSatisfy { $0 == paths.prefix(331160).path })
        }
    }

    /// The timeout must hold even when wine ignores the cancel: Wine is stopped, which frees it.
    @Test(.timeLimit(.minutes(1))) func timeoutStopsAWinebootThatIgnoresCancel() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let recorder = Recorder()
            let manager = PrefixManager(paths: paths, engine: engine,
                makeRunner: { prefix, _ in FakeRunner(prefix: prefix, recorder: recorder, hangsUntilStop: true) },
                winebootTimeout: .milliseconds(300))
            let started = ContinuousClock.now

            await #expect(throws: PrefixError.creationTimedOut(appID: 331160)) {
                try await manager.ensurePrefix(appID: 331160, recipe: .generic, gameDir: dir.appendingPathComponent("G"))
            }
            #expect(ContinuousClock.now - started < .seconds(5))
        }
    }

    @Test func lockSerializesCreation() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let recorder = Recorder()
            let manager = manager(paths, recorder)
            let recipe = Recipe.generic

            async let first = manager.ensurePrefix(
                appID: 1, recipe: recipe, gameDir: dir.appendingPathComponent("Games/1"))
            async let second = manager.ensurePrefix(
                appID: 2, recipe: recipe, gameDir: dir.appendingPathComponent("Games/2"))
            _ = try await (first, second)

            #expect(await recorder.runs.count == 2)
            #expect(await recorder.maxActive == 1)
        }
    }
}
