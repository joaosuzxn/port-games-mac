import Foundation

/// On-disk layout of the launcher's data.
///
/// Everything lives under one root (`~/Library/Application Support/PortGames` by default),
/// except the download cache, which is kept separately so it can be cleared freely.
/// Prefixes (and the saves inside them) and local recipes are never touched by uninstall/update,
/// which is why they sit outside `games/`.
public struct Paths: Sendable {
    public let root: URL
    public let cache: URL

    public init(root: URL, cache: URL) {
        self.root = root
        self.cache = cache
    }

    /// The real locations used by the app and by `launcherctl`.
    public static let standard: Paths = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Paths(
            root: home.appendingPathComponent("Library/Application Support/PortGames", isDirectory: true),
            cache: home.appendingPathComponent("Library/Caches/PortGames/artifacts", isDirectory: true)
        )
    }()

    /// Wine engines, one folder per engine ID.
    public var engines: URL { root.appendingPathComponent("engines", isDirectory: true) }
    /// Steam bridge files, one folder per engine ID.
    public var bridge: URL { root.appendingPathComponent("bridge", isDirectory: true) }
    /// Wine prefixes, one folder per app ID. Always on the internal disk.
    public var prefixes: URL { root.appendingPathComponent("prefixes", isDirectory: true) }
    /// Default library for game files, one folder per app ID.
    public var games: URL { root.appendingPathComponent("games", isDirectory: true) }
    /// Install state files, `<appID>.json`.
    public var state: URL { root.appendingPathComponent("state", isDirectory: true) }
    /// Local recipes, `<appID>.json`.
    public var recipes: URL { root.appendingPathComponent("recipes", isDirectory: true) }
    /// Run logs, `<appID>.log`.
    public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }

    public func prefix(_ appID: UInt32) -> URL {
        prefixes.appendingPathComponent(String(appID), isDirectory: true)
    }

    /// Folder with the game files: inside `library` when the user chose one, else in `games`.
    public func gameDir(_ appID: UInt32, library: URL?) -> URL {
        (library ?? games).appendingPathComponent(String(appID), isDirectory: true)
    }

    public func stateFile(_ appID: UInt32) -> URL {
        state.appendingPathComponent("\(appID).json", isDirectory: false)
    }

    /// Creates the data folders and the download cache. Safe to call repeatedly.
    public func ensureCreated() throws {
        for url in [engines, bridge, prefixes, games, state, recipes, logs, cache] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
