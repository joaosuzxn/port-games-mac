import Foundation
import LauncherCore

// launcherctl: the launcher's engine from the terminal (the SwiftUI app is #9).

let paths = Paths.standard
let steamAppInfo = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Steam/appcache/appinfo.vdf")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func say(_ text: String, terminator: String = "\n") {
    FileHandle.standardOutput.write(Data((text + terminator).utf8))
}

func json<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

/// Download progress on one line.
let showProgress: @Sendable (Double) -> Void = { value in
    say(String(format: "\rdownloading… %5.1f%%", value * 100), terminator: value >= 1 ? "\n" : "")
}

let auth = SteamAuth(http: URLSessionHTTPClient(), store: KeychainTokenStore())

func session() async throws -> SteamSession {
    guard let session = try await auth.validSession() else { fail("not logged in to Steam: run `launcherctl login`") }
    return session
}

func appInfo(_ appID: UInt32) throws -> AppInfo {
    guard let info = try AppInfoReader.read(steamAppInfo)[appID] else {
        fail("Steam for Mac has no data for app \(appID) yet: open its page in Steam, then try again")
    }
    return info
}

func installer(_ appID: UInt32) async throws -> Installer {
    let tool = try await DepotDownloaderTool.install(
        paths: paths, log: paths.logs.appendingPathComponent("\(appID)-download.log"))
    return Installer(paths: paths, downloader: tool)
}

/// Stops the game's Wine when launcherctl is interrupted (Ctrl-C), instead of leaving it running.
func stopOnInterrupt(_ game: RunningGame) -> DispatchSourceSignal {
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT)
    source.setEventHandler {
        say("\nstopping…")
        Task {
            try? await game.stop()
            exit(130)
        }
    }
    source.resume()
    return source
}

let command: Command
do {
    command = try CLI.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail((error as? LocalizedError)?.errorDescription ?? "\(error)")
}

do {
    try paths.ensureCreated()
    switch command {
    case .login:
        let login = try await auth.beginQR()
        let png = paths.logs.appendingPathComponent("qr.png")
        let show: @Sendable (URL) throws -> Void = { url in
            try QRImage.png(for: url, scale: 10).write(to: png, options: .atomic)
            say("Scan this QR code with the Steam app on your phone: \(png.path)\n(\(url.absoluteString))")
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [png.path]
            try? open.run()
        }
        try show(login.challengeURL)
        let session = try await auth.waitForApproval(login) { url in try? show(url) }
        say("Logged in to Steam as \(session.accountName).")

    case .logout:
        try KeychainTokenStore().clear()
        say("Steam login forgotten.")

    case .library:
        let games = try await Library(http: URLSessionHTTPClient(), paths: paths, appInfoURL: steamAppInfo)
            .games(session: try await session())
        for game in games {
            let status: String
            switch game.status {
            case .notInstalled: status = "-"
            case .installing: status = "incomplete"
            case .installed: status = "installed"
            case .updateAvailable: status = "update"
            }
            say(String(game.appID).padding(toLength: 9, withPad: " ", startingAt: 0)
                + status.padding(toLength: 12, withPad: " ", startingAt: 0) + game.name)
        }
        say("\(games.count) games")

    case .install(let appID, let library):
        let info = try appInfo(appID)
        let state = try await installer(appID).install(
            info, session: try await session(), library: library, progress: showProgress)
        say("Installed \(info.name) (build \(state.buildID)) in \(state.installDir)")

    case .update(let appID):
        let info = try appInfo(appID)
        let state = try await installer(appID).update(info, session: try await session(), progress: showProgress)
        say("Updated \(info.name) to build \(state.buildID)")

    case .uninstall(let appID):
        try Installer(paths: paths, downloader: DepotDownloader(
            binary: URL(fileURLWithPath: "/nonexistent"), accountStore: DepotDownloaderAccountStore(file: URL(fileURLWithPath: "/nonexistent"))))
            .uninstall(appID)
        say("Uninstalled app \(appID); its saves (\(paths.prefix(appID).path)) and recipe stay.")

    case .play(let appID):
        say("Preparing the engine…")
        let engine = try await EngineArtifacts.ensureEngine(paths: paths)
        let game = try await GameLauncher(paths: paths, engine: engine, appInfoURL: steamAppInfo).play(appID: appID)
        say("Playing app \(appID) (Ctrl-C stops it). Log: \(paths.logs.appendingPathComponent("\(appID).log").path)")
        let interrupt = stopOnInterrupt(game)
        let status = try await game.wait()
        interrupt.cancel()
        try await game.stop()
        say("The game exited with code \(status).")

    case .status(let appID):
        if let state = try GameStateStore.load(appID, paths: paths) {
            say("install: " + (try json(state)))
        } else {
            say("install: not installed")
        }
        say("recipe: " + (try json(RecipeStore(paths: paths).recipe(for: appID))))

    case .recipe(let appID, let edits):
        let store = RecipeStore(paths: paths)
        var recipe = store.recipe(for: appID)
        if !edits.show {
            recipe = edits.applied(to: recipe)
            try store.saveLocal(recipe, for: appID)
            say("Saved \(paths.recipes.appendingPathComponent("\(appID).json").path)")
        }
        say(try json(recipe))
    }
} catch {
    fail("error: " + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
}
