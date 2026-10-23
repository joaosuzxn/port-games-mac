import Foundation
import Testing
@testable import LauncherCore

private let session = SteamSession(accountName: "joao", steamID: 76561198000000001, refreshToken: jwt(), accessToken: "access-1")

private let ownedGames = FakeHTTP.Response(json: """
    {"response":{"game_count":3,"games":[
      {"appid":331160,"name":"Cars","playtime_forever":10},
      {"appid":480,"name":"Spacewar","playtime_forever":0},
      {"appid":1174180,"name":"Red Dead Redemption 2","playtime_forever":0}]}}
    """)

private func makePaths(in dir: URL) throws -> Paths {
    let paths = Paths(root: dir.appendingPathComponent("PortGames"), cache: dir.appendingPathComponent("Cache"))
    try paths.ensureCreated()
    return paths
}

private func state(_ appID: UInt32, build: UInt64, complete: Bool = true) -> GameState {
    GameState(appID: appID, installDir: "/G/\(appID)", buildID: build, depotManifests: [:], installedAt: Date(), complete: complete)
}

private func appInfo(_ appID: UInt32, build: UInt64) -> AppInfo {
    AppInfo(appID: appID, name: "", oslist: ["windows"], launch: [], publicBuildID: build, depots: [])
}

@Suite("Library")
struct LibraryTests {
    @Test func ownedGamesMergedWithAppInfo() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let http = FakeHTTP()
            await http.on("GetOwnedGames", ownedGames)
            // Cars installed at an older build; Spacewar mid-download; RDR2 not installed.
            try GameStateStore.save(state(331160, build: 400000), paths: paths)
            try GameStateStore.save(state(480, build: 1, complete: false), paths: paths)
            let library = Library(http: http, paths: paths) { [331160: appInfo(331160, build: 454676), 480: appInfo(480, build: 1)] }

            let games = try await library.games(session: session)

            #expect(games.map(\.name) == ["Cars", "Red Dead Redemption 2", "Spacewar"])
            let byID = Dictionary(uniqueKeysWithValues: games.map { ($0.appID, $0) })
            #expect(byID[331160]?.status == .updateAvailable)
            #expect(byID[331160]?.info?.publicBuildID == 454676)
            #expect(byID[480]?.status == .installing)
            #expect(byID[1174180]?.status == .notInstalled)
            #expect(byID[1174180]?.info == nil)

            let fields = await http.fields(of: 0)
            #expect(fields["access_token"] == "access-1")
            #expect(fields["steamid"] == "76561198000000001")
            #expect(fields["include_appinfo"] == "1")
            #expect(fields["include_played_free_games"] == "1")
        }
    }

    @Test func upToDateIsInstalled() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = try makePaths(in: dir)
            let http = FakeHTTP()
            await http.on("GetOwnedGames", ownedGames)
            try GameStateStore.save(state(331160, build: 454676), paths: paths)
            let library = Library(http: http, paths: paths) { [331160: appInfo(331160, build: 454676)] }

            let cars = try await library.games(session: session).first { $0.appID == 331160 }
            #expect(cars?.status == .installed)
        }
    }

    @Test func coverURL() {
        #expect(Library.coverURL(331160).absoluteString
            == "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/331160/library_600x900.jpg")
    }

    @Test func unauthorizedAsksForLogin() async throws {
        try await withAsyncScratchDirectory { dir in
            let http = FakeHTTP()
            await http.on("GetOwnedGames", FakeHTTP.Response(status: 401, json: "", eresult: nil))
            let library = Library(http: http, paths: try makePaths(in: dir)) { [:] }

            await #expect(throws: SteamAuthError.notLoggedIn) { try await library.games(session: session) }
        }
    }

    @Test func unreadableAppInfoStillListsTheGames() async throws {
        try await withAsyncScratchDirectory { dir in
            let http = FakeHTTP()
            await http.on("GetOwnedGames", ownedGames)
            let library = Library(http: http, paths: try makePaths(in: dir)) { throw AppInfoError.truncated }

            let games = try await library.games(session: session)
            #expect(games.count == 3)
            #expect(games.allSatisfy { $0.info == nil })
        }
    }
}
