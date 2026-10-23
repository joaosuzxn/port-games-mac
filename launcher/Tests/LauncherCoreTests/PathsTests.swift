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

@Suite("Paths")
struct PathsTests {
    @Test func pathsLayout() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            let root = paths.root.path

            #expect(paths.engines.path == "\(root)/engines")
            #expect(paths.bridge.path == "\(root)/bridge")
            #expect(paths.prefixes.path == "\(root)/prefixes")
            #expect(paths.games.path == "\(root)/games")
            #expect(paths.state.path == "\(root)/state")
            #expect(paths.recipes.path == "\(root)/recipes")
            #expect(paths.logs.path == "\(root)/logs")

            #expect(paths.prefix(331160).path == "\(root)/prefixes/331160")
            #expect(paths.gameDir(331160, library: nil).path == "\(root)/games/331160")
            let library = dir.appendingPathComponent("ExternalDisk/Library")
            #expect(paths.gameDir(331160, library: library).path == "\(library.path)/331160")
            #expect(paths.stateFile(331160).path == "\(root)/state/331160.json")
        }
    }

    @Test func standardPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let standard = Paths.standard
        #expect(standard.root.path == home.path + "/Library/Application Support/PortGames")
        #expect(standard.cache.path == home.path + "/Library/Caches/PortGames/artifacts")
    }

    @Test func ensureCreatedMakesDirectories() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            try paths.ensureCreated()
            // Calling it twice must be harmless.
            try paths.ensureCreated()

            for url in [paths.engines, paths.bridge, paths.prefixes, paths.games,
                        paths.state, paths.recipes, paths.logs, paths.cache] {
                var isDirectory: ObjCBool = false
                #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
                #expect(isDirectory.boolValue)
            }
        }
    }
}

@Suite("GameStateStore")
struct GameStateTests {
    private func sampleState() -> GameState {
        GameState(
            appID: 331160,
            installDir: "Cars",
            buildID: 12_345_678,
            depotManifests: [331161: 9_876_543_210, 331162: 42],
            installedAt: Date(timeIntervalSince1970: 1_760_000_000),
            complete: true
        )
    }

    @Test func stateRoundTrip() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            let state = sampleState()

            try GameStateStore.save(state, paths: paths)
            let loaded = try GameStateStore.load(331160, paths: paths)

            #expect(loaded == state)
            #expect(loaded?.depotManifests == [331161: 9_876_543_210, 331162: 42])
        }
    }

    @Test func stateFileIsReadableJSON() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            try GameStateStore.save(sampleState(), paths: paths)

            let data = try Data(contentsOf: paths.stateFile(331160))
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["appID"] as? Int == 331160)
            // Depot IDs are string keys of a JSON object, not a flat key/value array.
            let manifests = try #require(object["depotManifests"] as? [String: Any])
            #expect(manifests["331161"] as? UInt64 == 9_876_543_210)
            #expect(manifests["331162"] as? Int == 42)
        }
    }

    @Test func stateWithInvalidDepotKeyFailsToLoad() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            try paths.ensureCreated()
            let json = #"{"appID":1,"installDir":"X","buildID":1,"installedAt":0,"complete":true,"depotManifests":{"abc":1}}"#
            try Data(json.utf8).write(to: paths.stateFile(1))

            #expect(throws: DecodingError.self) {
                try GameStateStore.load(1, paths: paths)
            }
        }
    }

    @Test func stateMissingIsNil() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            let loaded = try GameStateStore.load(331160, paths: paths)
            #expect(loaded == nil)
        }
    }

    @Test func stateAtomic() throws {
        try withTemporaryDirectory { dir in
            let paths = makePaths(in: dir)
            try GameStateStore.save(sampleState(), paths: paths)
            // Overwriting an existing state must also leave no temporary file behind.
            var updated = sampleState()
            updated.complete = false
            try GameStateStore.save(updated, paths: paths)

            let names = try FileManager.default.contentsOfDirectory(atPath: paths.state.path)
            #expect(names == ["331160.json"])
            let loaded = try GameStateStore.load(331160, paths: paths)
            #expect(loaded?.complete == false)
        }
    }
}
