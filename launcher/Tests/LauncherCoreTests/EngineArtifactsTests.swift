import Foundation
import Testing
@testable import LauncherCore

@Suite("Engine artifacts")
struct EngineArtifactsTests {
    /// The same pins as the Python builder (`tools/builder/artifacts.json`): one engine for both.
    @Test func matchesTheBuilder() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: repo.appendingPathComponent("tools/builder/artifacts.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [String: String]])

        for (key, artifact) in [("template", EngineArtifacts.template), ("engine", EngineArtifacts.engine)] {
            #expect(json[key]?["file"] == artifact.file)
            #expect(json[key]?["sha256"] == artifact.sha256)
            #expect(json[key]?["url"] == artifact.url?.absoluteString)
        }
        #expect(EngineArtifacts.engineID == "ws12-wine-sikarugir-11.0_1")
    }

    /// Two games played at once on a fresh Mac: one engine install, not two racing over the same files.
    @Test func concurrentFirstInstallsShareOneEngine() async throws {
        try await withAsyncScratchDirectory { dir in
            let paths = Paths(root: dir.appendingPathComponent("PortGames"), cache: dir.appendingPathComponent("Cache"))
            let sources = dir.appendingPathComponent("artifacts", isDirectory: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            let templateFile = try makeTemplateTar(in: sources, name: "t.tar.xz")
            let engineFile = try makeEngineTar(in: sources, name: "e.tar.xz")
            let template = Artifact(file: "t.tar.xz", sha256: try ArtifactStore.sha256Hex(of: templateFile), url: nil)
            let engine = Artifact(file: "e.tar.xz", sha256: try ArtifactStore.sha256Hex(of: engineFile), url: nil)

            let engines = try await withThrowingTaskGroup(of: Engine.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        try await EngineArtifacts.ensureEngine(
                            paths: paths, template: template, engine: engine, localSources: [sources])
                    }
                }
                return try await group.reduce(into: [Engine]()) { $0.append($1) }
            }

            #expect(Set(engines.map(\.root)).count == 1)
            #expect(try FileManager.default.contentsOfDirectory(atPath: paths.engines.path)
                .filter { !$0.hasPrefix(".install") } == [EngineArtifacts.engineID])
        }
    }
}
