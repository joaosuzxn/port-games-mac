import Foundation
import Testing
@testable import LauncherCore

/// Creates a unique temporary directory and removes it when the body returns.
private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("launcher-core-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

private func makePaths(in dir: URL) -> Paths {
    Paths(
        root: dir.appendingPathComponent("PortGames", isDirectory: true),
        cache: dir.appendingPathComponent("Cache", isDirectory: true)
    )
}

private func registryKey(_ recipe: Recipe, _ hive: RegistryKey.Hive, _ key: String) -> RegistryKey? {
    recipe.registry.first { $0.hive == hive && $0.key == key }
}

@Suite("Recipe")
struct RecipeTests {
    @Test func carrosRecipe() throws {
        try withTemporaryDirectory { dir in
            let store = RecipeStore(paths: makePaths(in: dir))
            let recipe = store.recipe(for: 331160)

            #expect(store.hasBundled(331160))
            #expect(recipe.appID == 331160)
            #expect(recipe.renderer == .wined3d)
            #expect(recipe.emulateModeset)
            #expect(recipe.cdLabel == "DISC2")
            #expect(recipe.executable == "Cars.exe")

            let display = registryKey(recipe, .user, "Software\\THQ\\Cars\\Settings\\Display")
            #expect(display?.values["Resolution"] == .dword(14))
            #expect(display?.values["MultiSampleType"] == .dword(4))
            #expect(display?.values["FullscreenEffects"] == .dword(1))

            let winebus = registryKey(recipe, .system, "System\\ControlSet001\\Services\\winebus")
            #expect(winebus?.values["Enable SDL"] == .dword(1))
            #expect(winebus?.values["Map Controllers"] == .dword(1))

            // The X11 driver tweak is the `emulateModeset` flag, not a registry entry.
            #expect(registryKey(recipe, .user, "Software\\Wine\\X11 Driver") == nil)
        }
    }

    @Test func spacewarRecipe() throws {
        try withTemporaryDirectory { dir in
            let store = RecipeStore(paths: makePaths(in: dir))
            let recipe = store.recipe(for: 480)

            #expect(store.hasBundled(480))
            #expect(recipe.appID == 480)
            #expect(recipe.executable == "SteamworksExample.exe")
            #expect(recipe.renderer == .wined3d)
            #expect(recipe.emulateModeset)
            #expect(recipe.cdLabel == nil)
            #expect(recipe.registry.isEmpty)
        }
    }

    @Test func genericFallback() throws {
        try withTemporaryDirectory { dir in
            let store = RecipeStore(paths: makePaths(in: dir))

            #expect(!store.hasBundled(999_999))
            #expect(store.recipe(for: 999_999) == Recipe.generic)
            #expect(Recipe.generic.renderer == .wined3d)
            #expect(Recipe.generic.emulateModeset)
            #expect(Recipe.generic.registry.isEmpty)
        }
    }

    @Test func localOverridesBundled() throws {
        try withTemporaryDirectory { dir in
            let store = RecipeStore(paths: makePaths(in: dir))
            var local = store.recipe(for: 331160)
            local.renderer = .d9vk

            try store.saveLocal(local, for: 331160)

            #expect(store.recipe(for: 331160).renderer == .d9vk)
            #expect(store.recipe(for: 331160) == local)
            // The bundled recipe is still there, just shadowed.
            #expect(store.hasBundled(331160))
        }
    }

    @Test func localRecipeForUnknownGame() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            let store = RecipeStore(paths: paths)
            let local = Recipe(
                appID: 42, renderer: .dxvk, emulateModeset: false, cdLabel: nil,
                executable: "Game.exe", arguments: ["-windowed"],
                environment: ["WINEDEBUG": "-all"], dllOverrides: ["d3d9": "native"],
                registry: [RegistryKey(hive: .user, key: "Software\\Game", values: ["Name": .string("x"), "Level": .dword(7)])]
            )

            try store.saveLocal(local, for: 42)

            #expect(store.recipe(for: 42) == local)
            #expect(!store.hasBundled(42))
            #expect(FileManager.default.fileExists(atPath: paths.recipes.appendingPathComponent("42.json").path))
        }
    }

    @Test func corruptLocalFallsBackToBundled() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            try paths.ensureCreated()
            try Data("{ not json".utf8).write(to: paths.recipes.appendingPathComponent("331160.json"))
            let store = RecipeStore(paths: paths)

            #expect(store.recipe(for: 331160).executable == "Cars.exe")
        }
    }

    @Test func dwordValuesStayNumbersInJSON() throws {
        let key = RegistryKey(hive: .user, key: "Software\\X", values: ["Number": .dword(4_294_967_295), "Text": .string("y")])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(key)

        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let values = try #require(object["values"] as? [String: Any])
        #expect(values["Number"] as? UInt32 == 4_294_967_295)
        #expect(values["Text"] as? String == "y")
        #expect(object["hive"] as? String == "user")
        #expect(try JSONDecoder().decode(RegistryKey.self, from: data) == key)
    }

    @Test func dwordOutOfRange() {
        func decode(_ literal: String) throws -> RegistryKey {
            let json = #"{"hive":"user","key":"Software\\X","values":{"V":\#(literal)}}"#
            return try JSONDecoder().decode(RegistryKey.self, from: Data(json.utf8))
        }

        #expect(throws: DecodingError.self) { try decode("-1") }
        #expect(throws: DecodingError.self) { try decode("4294967296") }
        #expect(throws: DecodingError.self) { try decode("1.5") }
        #expect(throws: DecodingError.self) { try decode("true") }
        #expect(throws: DecodingError.self) { try decode("null") }

        #expect(throws: Never.self) { try decode("0") }
        #expect(throws: Never.self) { try decode("4294967295") }
        #expect(throws: Never.self) { try decode("\"text\"") }
    }
}
