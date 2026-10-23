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
}
