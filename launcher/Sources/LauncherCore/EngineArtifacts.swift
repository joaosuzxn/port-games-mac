import Foundation

/// The shared engine the launcher installs: Sikarugir's template (frameworks, graphics layers, Vulkan)
/// and its Wine 11 build. Same pins as `tools/builder/artifacts.json`.
public enum EngineArtifacts {
    public static let engineID = "ws12-wine-sikarugir-11.0_1"

    public static let template = Artifact(
        file: "Template-1.0.24.tar.xz",
        sha256: "4b5f89eeb9ef139936bdfad33d9b420b05ea4597cb7d63376674f7a8e171321c",
        url: URL(string: "https://github.com/Sikarugir-App/Template/releases/download/v1.0/Template-1.0.24.tar.xz"))

    public static let engine = Artifact(
        file: "WS12WineSikarugir11.0_1.tar.xz",
        sha256: "67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e",
        url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir11.0_1.tar.xz"))

    /// The Python builder's cache, used before downloading anything.
    public static var localSources: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/portcarros/artefatos")]
    }

    /// The installed engine, installing it first if needed (two archives, ~1 minute to extract).
    public static func ensureEngine(paths: Paths) async throws -> Engine {
        try await ensureEngine(paths: paths, template: template, engine: engine, localSources: localSources)
    }

    static func ensureEngine(
        paths: Paths, template: Artifact, engine: Artifact, localSources: [URL],
        download: (URL, URL) async throws -> Void = ArtifactStore.downloadWithURLSession
    ) async throws -> Engine {
        if let installed = EngineInstaller.installed(id: engineID, paths: paths) { return installed }
        // One install at a time (two first plays, the CLI and the app): the archives and the engine folder
        // are shared. Whoever waited finds it installed.
        try FileManager.default.createDirectory(at: paths.engines, withIntermediateDirectories: true)
        let lock = try await FileLock.acquire(paths.engines.appendingPathComponent(".install.lock"))
        defer { lock.release() }
        if let installed = EngineInstaller.installed(id: engineID, paths: paths) { return installed }
        let templateFile = try await ArtifactStore.ensure(template, cache: paths.cache, localSources: localSources, download: download)
        let engineFile = try await ArtifactStore.ensure(engine, cache: paths.cache, localSources: localSources, download: download)
        return try EngineInstaller.install(template: templateFile, engine: engineFile, id: engineID, paths: paths)
    }
}
