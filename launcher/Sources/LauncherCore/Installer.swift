import Foundation

/// Downloads depots of an app into a folder. A protocol so the installer can be tested with a fake.
public protocol DepotDownloaderProtocol: Sendable {
    func download(
        appID: UInt32, depots: [Depot], into dir: URL, session: SteamSession,
        progress: @Sendable (Double) -> Void
    ) async throws
}

/// What the installer needs to know about a disk.
public protocol VolumeInspector: Sendable {
    /// `apfs`, `hfs`, `exfat`, `msdos`, …
    func fileSystem(at: URL) throws -> String
    func freeBytes(at: URL) throws -> UInt64
}

public struct SystemVolumeInspector: VolumeInspector {
    public init() {}

    public func fileSystem(at url: URL) throws -> String {
        (try url.resourceValues(forKeys: [.volumeTypeNameKey]).volumeTypeName ?? "").lowercased()
    }

    public func freeBytes(at url: URL) throws -> UInt64 {
        UInt64(max(try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? 0, 0))
    }
}

public enum InstallerError: Error, LocalizedError, Equatable {
    case unsupportedFileSystem(String)
    case notEnoughSpace(needed: UInt64, free: UInt64)
    case noWindowsDepots(UInt32)
    case notInstalled(UInt32)
    /// The game is running: its files are not touched until it is stopped.
    case gameRunning(UInt32)
    /// The recorded game folder is not one the launcher made (`…/<appID>`); it was not deleted.
    case unexpectedInstallDir(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileSystem(let name):
            return "games cannot be installed on a \(name) disk (Windows file names and links need APFS or Mac OS Extended)"
        case .notEnoughSpace(let needed, let free):
            return String(format: "not enough free space: %.1f GB more needed (%.1f GB needed, %.1f GB free)",
                Self.gigabytes(needed - min(free, needed)), Self.gigabytes(needed), Self.gigabytes(free))
        case .noWindowsDepots(let appID): return "app \(appID) has no Windows content to download"
        case .notInstalled(let appID): return "app \(appID) is not installed"
        case .gameRunning(let appID): return "app \(appID) is running; stop it first (launcherctl stop \(appID))"
        case .unexpectedInstallDir(let path): return "\(path) is not a game folder made by the launcher; nothing was deleted"
        }
    }

    private static func gigabytes(_ bytes: UInt64) -> Double { Double(bytes) / 1_000_000_000 }
}

/// Installs, updates and removes the Windows version of a game. Never touches the game's prefix
/// (saves) or its local recipe.
public struct Installer: Sendable {
    private let paths: Paths
    private let downloader: DepotDownloaderProtocol
    private let volumes: VolumeInspector
    private let language: String
    private let isGameRunning: @Sendable (UInt32) -> Bool

    static let refusedFileSystems: Set<String> = ["exfat", "msdos", "fat", "fat16", "fat32", "vfat", "ntfs"]

    public init(
        paths: Paths, downloader: DepotDownloaderProtocol, volumes: VolumeInspector = SystemVolumeInspector(),
        language: String = "english"
    ) {
        self.init(paths: paths, downloader: downloader, volumes: volumes, language: language) { appID in
            WineServerLock.holder(prefix: paths.prefix(appID), serverRoot: WineServerLock.defaultRoot) != nil
        }
    }

    init(
        paths: Paths, downloader: DepotDownloaderProtocol, volumes: VolumeInspector = SystemVolumeInspector(),
        language: String = "english", isGameRunning: @escaping @Sendable (UInt32) -> Bool
    ) {
        self.paths = paths
        self.downloader = downloader
        self.volumes = volumes
        self.language = language
        self.isGameRunning = isGameRunning
    }

    /// The per-game lock shared by install, update, uninstall and play (which only tries it).
    static func lockFile(_ appID: UInt32, paths: Paths) -> URL {
        paths.state.appendingPathComponent("\(appID).lock")
    }

    /// Downloads the game into `library/<appID>` (or the default games folder). The state is saved as
    /// incomplete first and marked complete only at the end, so an interrupted download is retried.
    public func install(
        _ info: AppInfo, session: SteamSession, library: URL?, progress: @Sendable (Double) -> Void
    ) async throws -> GameState {
        try await download(info, session: session, into: paths.gameDir(info.appID, library: library), progress: progress)
    }

    /// Downloads the current build over the installed one, in the same folder.
    public func update(
        _ info: AppInfo, session: SteamSession, progress: @Sendable (Double) -> Void
    ) async throws -> GameState {
        guard let state = try GameStateStore.load(info.appID, paths: paths) else {
            throw InstallerError.notInstalled(info.appID)
        }
        return try await download(
            info, session: session, into: URL(fileURLWithPath: state.installDir, isDirectory: true), progress: progress)
    }

    /// Deletes the game files and the install state. The prefix and the local recipe stay. Waits for a
    /// download of the game to end; refuses while the game runs.
    public func uninstall(_ appID: UInt32) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: paths.state, withIntermediateDirectories: true)
        let lock = try await FileLock.acquire(Self.lockFile(appID, paths: paths))
        defer { lock.release() }
        guard !isGameRunning(appID) else { throw InstallerError.gameRunning(appID) }
        if let state = try GameStateStore.load(appID, paths: paths) {
            let dir = URL(fileURLWithPath: state.installDir, isDirectory: true)
            // Only a folder the launcher made: `<library>/<appID>`.
            guard dir.lastPathComponent == String(appID) else {
                throw InstallerError.unexpectedInstallDir(state.installDir)
            }
            if fileManager.fileExists(atPath: dir.path) { try fileManager.removeItem(at: dir) }
        }
        let stateFile = paths.stateFile(appID)
        if fileManager.fileExists(atPath: stateFile.path) { try fileManager.removeItem(at: stateFile) }
    }

    /// The depots that make the Windows game: for Windows (or every OS), not a shared redistributable,
    /// not a DLC, without a language or in `language` (English when the game does not have it), and the
    /// 64-bit variant when there are 32- and 64-bit ones.
    public static func depots(for info: AppInfo, language: String) -> [Depot] {
        let candidates = info.depots.filter { depot in
            (depot.oslist.isEmpty || depot.oslist.contains("windows")) && !depot.shared && depot.fromApp == nil
                && depot.dlcAppID == nil && depot.publicManifest != nil
        }
        let languages = Set(candidates.compactMap(\.language))
        let wanted = languages.contains(language.lowercased()) ? language.lowercased() : "english"
        var chosen = candidates.filter { $0.language == nil || $0.language == wanted }
        if chosen.contains(where: { $0.osarch == "64" }) {
            chosen.removeAll { $0.osarch == "32" }
        }
        return chosen.sorted { $0.id < $1.id }
    }

    private func download(
        _ info: AppInfo, session: SteamSession, into dir: URL, progress: @Sendable (Double) -> Void
    ) async throws -> GameState {
        let depots = Self.depots(for: info, language: language)
        guard !depots.isEmpty else { throw InstallerError.noWindowsDepots(info.appID) }
        // One install or update of a game at a time (also across processes): two downloads into one
        // folder would overwrite each other, and the last to end would decide the state.
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
        let lock = try await FileLock.acquire(Self.lockFile(info.appID, paths: paths))
        defer { lock.release() }
        // Never write over the files of a running game.
        guard !isGameRunning(info.appID) else { throw InstallerError.gameRunning(info.appID) }
        try checkDisk(for: depots, at: dir)

        var state = GameState(
            appID: info.appID, installDir: dir.path, buildID: info.publicBuildID ?? 0,
            depotManifests: Dictionary(uniqueKeysWithValues: depots.compactMap { d in d.publicManifest.map { (d.id, $0) } }),
            installedAt: Date(), complete: false)
        try GameStateStore.save(state, paths: paths)

        try await downloader.download(appID: info.appID, depots: depots, into: dir, session: session, progress: progress)

        state.complete = true
        state.installedAt = Date()
        try GameStateStore.save(state, paths: paths)
        return state
    }

    /// Refuses FAT/exFAT/NTFS and too little space (sizes Steam gives, plus 5%), before anything is written.
    private func checkDisk(for depots: [Depot], at dir: URL) throws {
        var existing = dir
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            existing.deleteLastPathComponent()
        }
        let fileSystem = try volumes.fileSystem(at: existing)
        guard !Self.refusedFileSystems.contains(fileSystem) else { throw InstallerError.unsupportedFileSystem(fileSystem) }
        let size = depots.reduce(UInt64(0)) { $0 + ($1.maxSize ?? 0) }
        let needed = size + size / 20
        let free = try volumes.freeBytes(at: existing)
        guard free >= needed else { throw InstallerError.notEnoughSpace(needed: needed, free: free) }
    }
}
