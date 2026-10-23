import Foundation

/// One game of the account, as the library grid shows it.
public struct LibraryGame: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case notInstalled
        /// A download started and did not finish (it resumes).
        case installing
        case installed
        /// Installed, but Steam has a newer build (updating is the user's call).
        case updateAvailable
    }

    public var appID: UInt32
    public var name: String
    public var coverURL: URL
    public var info: AppInfo?
    public var state: GameState?
    public var status: Status
}

/// The games the Steam account owns, with what the Mac's Steam knows about them and their local state.
public struct Library: Sendable {
    private let api: SteamWebAPI
    private let paths: Paths
    private let appInfo: @Sendable () throws -> [UInt32: AppInfo]

    public init(http: HTTPClient, paths: Paths, appInfoURL: URL) {
        self.init(http: http, paths: paths) { try AppInfoReader.read(appInfoURL) }
    }

    init(http: HTTPClient, paths: Paths, appInfo: @escaping @Sendable () throws -> [UInt32: AppInfo]) {
        api = SteamWebAPI(http: http)
        self.paths = paths
        self.appInfo = appInfo
    }

    /// Sorted by name. Throws `SteamAuthError.notLoggedIn` when Steam refuses the access token.
    public func games(session: SteamSession) async throws -> [LibraryGame] {
        let reply = try await api.get("IPlayerService/GetOwnedGames", [
            "access_token": session.accessToken, "steamid": String(session.steamID),
            "include_appinfo": "1", "include_played_free_games": "1",
        ])
        if reply.status == 401 || reply.status == 403 { throw SteamAuthError.notLoggedIn }
        guard reply.status == 200, let owned = reply.response["games"] as? [[String: Any]] ?? (reply.response.isEmpty ? nil : [])
        else { throw SteamAuthError.unexpectedResponse("GetOwnedGames status \(reply.status)") }

        // The Mac's Steam cache adds launch options and builds; without it the grid still shows the games.
        let infos = (try? appInfo()) ?? [:]
        return owned.compactMap { game -> LibraryGame? in
            guard let appID = (game["appid"] as? NSNumber)?.uint32Value else { return nil }
            let info = infos[appID]
            let state = try? GameStateStore.load(appID, paths: paths)
            return LibraryGame(
                appID: appID, name: game["name"] as? String ?? info?.name ?? String(appID),
                coverURL: Self.coverURL(appID), info: info, state: state,
                status: Self.status(state: state, info: info))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The vertical 600×900 cover from Steam's CDN.
    public static func coverURL(_ appID: UInt32) -> URL {
        URL(string: "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/\(appID)/library_600x900.jpg")!
    }

    static func status(state: GameState?, info: AppInfo?) -> LibraryGame.Status {
        guard let state else { return .notInstalled }
        guard state.complete else { return .installing }
        if let latest = info?.publicBuildID, latest != state.buildID { return .updateAvailable }
        return .installed
    }
}
