import Foundation
import Testing
@testable import LauncherCore

@Suite("launcherctl arguments")
struct CLITests {
    @Test func cliParsesCommands() throws {
        #expect(try CLI.parse(["login"]) == .login)
        #expect(try CLI.parse(["logout"]) == .logout)
        #expect(try CLI.parse(["library"]) == .library)
        #expect(try CLI.parse(["install", "331160"]) == .install(appID: 331160, library: nil))
        #expect(try CLI.parse(["install", "331160", "--library", "/Volumes/Games"])
            == .install(appID: 331160, library: URL(fileURLWithPath: "/Volumes/Games", isDirectory: true)))
        #expect(try CLI.parse(["update", "331160"]) == .update(331160))
        #expect(try CLI.parse(["uninstall", "331160"]) == .uninstall(331160))
        #expect(try CLI.parse(["play", "480"]) == .play(480))
        #expect(try CLI.parse(["status", "480"]) == .status(480))
        #expect(try CLI.parse(["recipe", "331160", "--show"])
            == .recipe(appID: 331160, edits: RecipeEdits(show: true)))
        #expect(try CLI.parse([
            "recipe", "331160", "--renderer", "d9vk", "--emulate-modeset", "off",
            "--env", "DXVK_HUD=fps", "--env", "WINEDEBUG=+loaddll", "--dll", "d3d9=n,b",
        ]) == .recipe(appID: 331160, edits: RecipeEdits(
            renderer: .d9vk, emulateModeset: false,
            environment: ["DXVK_HUD": "fps", "WINEDEBUG": "+loaddll"], dllOverrides: ["d3d9": "n,b"])))
    }

    @Test(arguments: [
        [String](), ["dance"], ["install"], ["install", "abc"], ["install", "-1"], ["install", "1", "--library"],
        ["install", "1", "--bogus"], ["play", "1", "2"], ["login", "x"],
        ["recipe", "1", "--renderer", "metal"], ["recipe", "1", "--emulate-modeset", "maybe"],
        ["recipe", "1", "--env", "NOEQUALS"], ["recipe", "1", "--dll", "=x"],
    ])
    func invalidCommandsShowUsage(arguments: [String]) {
        #expect(throws: CLIError.self) { try CLI.parse(arguments) }
    }

    @Test func usageListsEveryCommand() {
        for command in ["login", "logout", "library", "install", "update", "uninstall", "play", "status", "recipe"] {
            #expect(CLI.usage.contains("launcherctl \(command)"), "\(command)")
        }
    }

    @Test func recipeCommandMergesOverEffective() throws {
        try withScratchDirectory { dir in
            let paths = Paths(root: dir.appendingPathComponent("PortGames"), cache: dir.appendingPathComponent("Cache"))
            let store = RecipeStore(paths: paths)
            guard case .recipe(_, let edits) = try CLI.parse(["recipe", "331160", "--renderer", "d9vk", "--env", "A=1"])
            else { Issue.record("not a recipe command"); return }

            let edited = edits.applied(to: store.recipe(for: 331160))
            try store.saveLocal(edited, for: 331160)

            let saved = store.recipe(for: 331160)
            #expect(saved.renderer == .d9vk)
            #expect(saved.environment["A"] == "1")
            // Everything else comes from the effective (bundled) recipe.
            #expect(saved.cdLabel == "DISC2")
            #expect(saved.executable == "Cars.exe")
            #expect(saved.emulateModeset)
            #expect(saved.registry == store.recipe(for: 331160).registry)

            // A second edit builds on the saved one.
            guard case .recipe(_, let more) = try CLI.parse(["recipe", "331160", "--emulate-modeset", "off"])
            else { return }
            let again = more.applied(to: store.recipe(for: 331160))
            #expect(again.renderer == .d9vk && !again.emulateModeset && again.environment["A"] == "1")
        }
    }
}
