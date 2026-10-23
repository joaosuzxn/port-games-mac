import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fakes

private actor FakeDownloader: DepotDownloaderProtocol {
    private(set) var calls: [(appID: UInt32, depots: [UInt32], dir: URL)] = []
    private var active = 0
    private(set) var maxActive = 0
    var delay: Duration = .zero
    /// Fails the call with this number (1-based) after reporting half the progress.
    var failOnCall: Int?
    var writes = true

    init(failOnCall: Int? = nil) { self.failOnCall = failOnCall }

    nonisolated func download(
        appID: UInt32, depots: [Depot], into dir: URL, session: SteamSession,
        progress: @Sendable (Double) -> Void
    ) async throws {
        let call = await record(appID, depots.map(\.id), dir)
        defer { Task { await self.finished() } }
        try await Task.sleep(for: await delay)
        progress(0.5)
        if await failOnCall == call { throw URLError(.networkConnectionLost) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("game".utf8).write(to: dir.appendingPathComponent("Cars.exe"))
        progress(1)
    }

    private func record(_ appID: UInt32, _ depots: [UInt32], _ dir: URL) -> Int {
        calls.append((appID, depots, dir))
        active += 1
        maxActive = max(maxActive, active)
        return calls.count
    }

    private func finished() { active -= 1 }
    func setDelay(_ d: Duration) { delay = d }
}

private struct FakeVolumes: VolumeInspector {
    var fileSystem = "apfs"
    var free: UInt64 = 500_000_000_000
    func fileSystem(at: URL) throws -> String { fileSystem }
    func freeBytes(at: URL) throws -> UInt64 { free }
}

// MARK: - Fixtures

private let session = SteamSession(accountName: "joao", steamID: 1, refreshToken: "r", accessToken: "a")

/// Cars as appinfo.vdf describes it: a base depot, one per language, the shared DirectX redist.
private func carros(build: UInt64 = 454676) -> AppInfo {
    AppInfo(
        appID: 331160, name: "Cars", oslist: ["windows"], launch: [], publicBuildID: build,
        depots: [
            Depot(id: 228990, oslist: ["windows"], osarch: nil, publicManifest: nil, maxSize: nil,
                fromApp: 228980, shared: true),
            Depot(id: 331161, oslist: [], osarch: nil, publicManifest: 11, maxSize: 1_000_000_000),
            Depot(id: 331162, oslist: ["windows"], osarch: nil, publicManifest: 12, maxSize: 100_000_000,
                language: "english"),
            Depot(id: 331163, oslist: ["windows"], osarch: nil, publicManifest: 13, maxSize: 1_500_000_000,
                language: "french"),
            Depot(id: 331170, oslist: ["windows"], osarch: nil, publicManifest: 20, maxSize: 5, dlcAppID: 331171),
            Depot(id: 331180, oslist: ["macos"], osarch: nil, publicManifest: 30, maxSize: 7),
        ])
}

private func makePaths(in dir: URL) throws -> Paths {
    let paths = Paths(root: dir.appendingPathComponent("PortGames"), cache: dir.appendingPathComponent("Cache"))
    try paths.ensureCreated()
    return paths
}

// MARK: - Tests

@Suite("Installer")
struct InstallerTests {
    @Test func picksWindowsDepots() {
        #expect(Installer.depots(for: carros(), language: "english").map(\.id) == [331161, 331162])
        #expect(Installer.depots(for: carros(), language: "french").map(\.id) == [331161, 331163])
        // A language the game does not have falls back to English.
        #expect(Installer.depots(for: carros(), language: "korean").map(\.id) == [331161, 331162])
    }

    @Test func prefers64BitVariant() {
        let info = AppInfo(
            appID: 1, name: "", oslist: [], launch: [], publicBuildID: 1,
            depots: [
                Depot(id: 2, oslist: ["windows"], osarch: "32", publicManifest: 1, maxSize: 1),
                Depot(id: 3, oslist: ["windows"], osarch: "64", publicManifest: 1, maxSize: 1),
                Depot(id: 4, oslist: ["windows"], osarch: nil, publicManifest: 1, maxSize: 1),
            ])
        #expect(Installer.depots(for: info, language: "english").map(\.id) == [3, 4])
    }

    @Test func installsAndMarksComplete() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let downloader = FakeDownloader()
            let installer = Installer(paths: paths, downloader: downloader, volumes: FakeVolumes())

            let state = try await installer.install(carros(), session: session, library: nil) { _ in }

            #expect(state.complete)
            #expect(state.buildID == 454676)
            #expect(state.depotManifests == [331161: 11, 331162: 12])
            #expect(state.installDir == paths.gameDir(331160, library: nil).path)
            #expect(try GameStateStore.load(331160, paths: paths) == state)
            let calls = await downloader.calls
            #expect(calls.map(\.depots) == [[331161, 331162]])
            #expect(calls.first?.dir == paths.gameDir(331160, library: nil))
        }
    }

    @Test func refusesExFAT() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let downloader = FakeDownloader()
            let installer = Installer(paths: paths, downloader: downloader, volumes: FakeVolumes(fileSystem: "exfat"))

            await #expect(throws: InstallerError.unsupportedFileSystem("exfat")) {
                try await installer.install(carros(), session: session, library: dir.appendingPathComponent("USB")) { _ in }
            }
            #expect(await downloader.calls.isEmpty)
            #expect(try GameStateStore.load(331160, paths: paths) == nil)
        }
    }

    @Test func refusesInsufficientSpace() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let downloader = FakeDownloader()
            // Needs 1.1 GB + 5%; only 0.5 GB free.
            let installer = Installer(paths: paths, downloader: downloader, volumes: FakeVolumes(free: 500_000_000))

            do {
                _ = try await installer.install(carros(), session: session, library: nil) { _ in }
                Issue.record("expected an error")
            } catch let error as InstallerError {
                guard case .notEnoughSpace(let needed, let free) = error else {
                    Issue.record("wrong error \(error)")
                    return
                }
                #expect(needed == 1_155_000_000)
                #expect(free == 500_000_000)
                #expect(error.localizedDescription.contains("0.7 GB"), "\(error.localizedDescription)")
            }
            #expect(await downloader.calls.isEmpty)
        }
    }

    @Test func interruptedNotComplete() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let downloader = FakeDownloader(failOnCall: 1)
            let installer = Installer(paths: paths, downloader: downloader, volumes: FakeVolumes())

            await #expect(throws: URLError.self) {
                try await installer.install(carros(), session: session, library: nil) { _ in }
            }
            let saved = try #require(try GameStateStore.load(331160, paths: paths))
            #expect(!saved.complete)

            // Trying again downloads again, into the same folder (DepotDownloader resumes there).
            let state = try await installer.install(carros(), session: session, library: nil) { _ in }
            #expect(state.complete)
            let calls = await downloader.calls
            #expect(calls.count == 2)
            #expect(calls[0].dir == calls[1].dir)
        }
    }

    /// Installing the same game twice at once must not run two downloads into one folder.
    @Test func sameGameInstallsOneAtATime() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let downloader = FakeDownloader()
            await downloader.setDelay(.milliseconds(200))
            let installer = Installer(paths: paths, downloader: downloader, volumes: FakeVolumes())

            async let first = installer.install(carros(), session: session, library: nil) { _ in }
            async let second = installer.install(carros(), session: session, library: nil) { _ in }
            _ = try await (first, second)

            #expect(await downloader.calls.count == 2)
            #expect(await downloader.maxActive == 1)
        }
    }

    @Test func uninstallKeepsPrefixAndRecipe() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let installer = Installer(paths: paths, downloader: FakeDownloader(), volumes: FakeVolumes())
            let library = dir.appendingPathComponent("Games", isDirectory: true)
            _ = try await installer.install(carros(), session: session, library: library) { _ in }
            let save = paths.prefix(331160).appendingPathComponent("drive_c/users/u/Documents/save.dat")
            try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("save".utf8).write(to: save)
            try RecipeStore(paths: paths).saveLocal(.generic, for: 331160)
            try Data("mine".utf8).write(to: library.appendingPathComponent("other.txt"))

            try installer.uninstall(331160)

            #expect(!FileManager.default.fileExists(atPath: library.appendingPathComponent("331160").path))
            #expect(try GameStateStore.load(331160, paths: paths) == nil)
            #expect(FileManager.default.fileExists(atPath: save.path))
            #expect(FileManager.default.fileExists(atPath: paths.recipes.appendingPathComponent("331160.json").path))
            // The library folder and whatever else is in it stay.
            #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent("other.txt").path))
        }
    }

    @Test func uninstallRefusesAFolderThatIsNotTheGames() throws {
        try withScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            // A state file pointing at some folder of the user (corrupt or edited): never deleted.
            let precious = dir.appendingPathComponent("Documents", isDirectory: true)
            try FileManager.default.createDirectory(at: precious, withIntermediateDirectories: true)
            try GameStateStore.save(GameState(
                appID: 331160, installDir: precious.path, buildID: 1, depotManifests: [:], installedAt: Date(),
                complete: true), paths: paths)
            let installer = Installer(paths: paths, downloader: FakeDownloader(), volumes: FakeVolumes())

            #expect(throws: InstallerError.self) { try installer.uninstall(331160) }
            #expect(FileManager.default.fileExists(atPath: precious.path))
        }
    }

    @Test func updateKeepsPrefixAndRecipe() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let downloader = FakeDownloader()
            let installer = Installer(paths: paths, downloader: downloader, volumes: FakeVolumes())
            let library = dir.appendingPathComponent("Games", isDirectory: true)
            _ = try await installer.install(carros(build: 400000), session: session, library: library) { _ in }
            let save = paths.prefix(331160).appendingPathComponent("save.dat")
            try FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("save".utf8).write(to: save)
            try RecipeStore(paths: paths).saveLocal(.generic, for: 331160)

            let state = try await installer.update(carros(build: 454676), session: session) { _ in }

            #expect(state.buildID == 454676)
            #expect(state.complete)
            // Updated where it was installed, not in the default folder.
            #expect(await downloader.calls.last?.dir == library.appendingPathComponent("331160", isDirectory: true))
            #expect(FileManager.default.fileExists(atPath: save.path))
            #expect(FileManager.default.fileExists(atPath: paths.recipes.appendingPathComponent("331160.json").path))
        }
    }

    @Test func updateWithoutInstallIsAnError() async throws {
        try await withAsyncScratchDirectory { dir in
            let installer = Installer(paths: try makePaths(in: dir), downloader: FakeDownloader(), volumes: FakeVolumes())
            await #expect(throws: InstallerError.notInstalled(331160)) {
                try await installer.update(carros(), session: session) { _ in }
            }
        }
    }

    @Test func nothingToDownloadIsAnError() async throws {
        try await withAsyncScratchDirectory { dir in
            let installer = Installer(paths: try makePaths(in: dir), downloader: FakeDownloader(), volumes: FakeVolumes())
            let macOnly = AppInfo(appID: 9, name: "", oslist: ["macos"], launch: [], publicBuildID: 1,
                depots: [Depot(id: 10, oslist: ["macos"], osarch: nil, publicManifest: 1, maxSize: 1)])
            await #expect(throws: InstallerError.noWindowsDepots(9)) {
                try await installer.install(macOnly, session: session, library: nil) { _ in }
            }
        }
    }
}
