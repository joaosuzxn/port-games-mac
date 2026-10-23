import CryptoKit
import Foundation
import Testing
@testable import LauncherCore

// MARK: - Fixtures

private struct FixtureError: Error, CustomStringConvertible {
    let description: String
}

/// Builds `target` with the system tar, like `tools/builder/test_bundle.py` does.
private func makeTarXZ(from source: URL, root: String, to target: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = ["-cJf", target.path, "-C", source.path, root]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw FixtureError(description: "tar -cJf failed with status \(process.terminationStatus)")
    }
}

private func write(_ text: String, to url: URL, executable: Bool = false) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    if executable {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

/// A fake Sikarugir template: one root `Template-1.0.24.app/` with frameworks (one symlink),
/// renderers and a launcher that the engine must NOT pick up.
private func makeTemplateTar(in dir: URL, name: String = "template.tar.xz") throws -> URL {
    let source = dir.appendingPathComponent("template-src-\(UUID().uuidString)", isDirectory: true)
    let contents = source.appendingPathComponent("Template-1.0.24.app/Contents", isDirectory: true)
    try write("framework", to: contents.appendingPathComponent("Frameworks/libfoo.1.dylib"))
    try FileManager.default.createSymbolicLink(
        atPath: contents.appendingPathComponent("Frameworks/libfoo.dylib").path,
        withDestinationPath: "libfoo.1.dylib")
    let renderer = contents.appendingPathComponent("SharedSupport/renderer", isDirectory: true)
    try write("d9vk dll", to: renderer.appendingPathComponent("d9vk/wine/i386-windows/d3d9.dll"))
    try write("dxvk dll", to: renderer.appendingPathComponent("dxvk/wine/i386-windows/d3d9.dll"))
    try write("framework", to: renderer.appendingPathComponent("d3dmetal/external/libd3dshared.dylib"))
    try write("d3dmetal dll", to: renderer.appendingPathComponent("d3dmetal/wine/x86_64-windows/d3d11.dll"))
    try write("#!/bin/sh\n", to: contents.appendingPathComponent("MacOS/launcher"), executable: true)
    let tar = dir.appendingPathComponent(name)
    try makeTarXZ(from: source, root: "Template-1.0.24.app", to: tar)
    return tar
}

/// A fake Wine engine: one root `wswine.bundle/` with `bin/wine`, `bin/wineserver` and `lib/`.
private func makeEngineTar(in dir: URL, name: String = "engine.tar.xz", withWine: Bool = true) throws -> URL {
    let source = dir.appendingPathComponent("engine-src-\(UUID().uuidString)", isDirectory: true)
    let bundle = source.appendingPathComponent("wswine.bundle", isDirectory: true)
    if withWine {
        try write("#!/bin/sh\n", to: bundle.appendingPathComponent("bin/wine"), executable: true)
    }
    try write("#!/bin/sh\n", to: bundle.appendingPathComponent("bin/wineserver"), executable: true)
    try write("lib", to: bundle.appendingPathComponent("lib/libwine.dylib"))
    let tar = dir.appendingPathComponent(name)
    try makeTarXZ(from: source, root: "wswine.bundle", to: tar)
    return tar
}

private func makePaths(in dir: URL) -> Paths {
    Paths(
        root: dir.appendingPathComponent("PortGames", isDirectory: true),
        cache: dir.appendingPathComponent("Cache", isDirectory: true)
    )
}

private func names(in directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
}

private struct NetworkDown: Error {}

private let engineID = "ws12-wine-sikarugir-11.0_1"

// MARK: - Engine install

@Suite("EngineInstaller")
struct EngineInstallerTests {
    @Test func installsLayout() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let template = try makeTemplateTar(in: dir)
            let engineTar = try makeEngineTar(in: dir)

            let engine = try EngineInstaller.install(
                template: template, engine: engineTar, id: engineID, paths: paths)

            #expect(engine.id == engineID)
            #expect(engine.root.path == paths.engines.appendingPathComponent(engineID).path)
            #expect(engine.wineBin.path == engine.root.path + "/wine/bin/wine")
            #expect(engine.wineserver.path == engine.root.path + "/wine/bin/wineserver")
            #expect(FileManager.default.isExecutableFile(atPath: engine.wineBin.path))
            #expect(FileManager.default.isExecutableFile(atPath: engine.wineserver.path))
            #expect(exists(engine.root.appendingPathComponent("wine/lib/libwine.dylib")))
            #expect(exists(engine.root.appendingPathComponent("Frameworks/libfoo.1.dylib")))
            #expect(exists(engine.root.appendingPathComponent("renderer/d9vk/wine/i386-windows/d3d9.dll")))

            // Only the three pieces land in the engine folder; the template's launcher does not.
            #expect(try names(in: engine.root) == ["Frameworks", "renderer", "wine"])
            // Nothing else is left next to it (no staging folders).
            #expect(try names(in: paths.engines) == [engineID])
        }
    }

    @Test func keepsFrameworkSymlinks() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let engine = try EngineInstaller.install(
                template: try makeTemplateTar(in: dir), engine: try makeEngineTar(in: dir),
                id: engineID, paths: paths)

            let link = engine.root.appendingPathComponent("Frameworks/libfoo.dylib")
            // A copy that followed the link would be a regular file with no destination.
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == "libfoo.1.dylib")
        }
    }

    @Test func rendererDirectories() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let engine = try EngineInstaller.install(
                template: try makeTemplateTar(in: dir), engine: try makeEngineTar(in: dir),
                id: engineID, paths: paths)

            let root = engine.root.path
            #expect(engine.rendererDir(.d9vk)?.path == root + "/renderer/d9vk/wine")
            #expect(engine.rendererDir(.dxvk)?.path == root + "/renderer/dxvk/wine")
            // D3DMetal needs its `external/` frameworks next to `wine/`, so it is the folder itself.
            #expect(engine.rendererDir(.d3dmetal)?.path == root + "/renderer/d3dmetal")
            #expect(engine.rendererDir(.wined3d) == nil)
            for renderer in [Renderer.d9vk, .dxvk, .d3dmetal] {
                let folder = try #require(engine.rendererDir(renderer))
                #expect(exists(folder), "\(renderer) folder should exist in the installed engine")
            }
        }
    }

    @Test func idempotent() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let template = try makeTemplateTar(in: dir)
            let engineTar = try makeEngineTar(in: dir)
            let first = try EngineInstaller.install(
                template: template, engine: engineTar, id: engineID, paths: paths)
            let marker = first.root.appendingPathComponent("marker.txt")
            try write("kept", to: marker)

            // The archives are gone: a second call must not even look at them.
            try FileManager.default.removeItem(at: template)
            try FileManager.default.removeItem(at: engineTar)
            let second = try EngineInstaller.install(
                template: template, engine: engineTar, id: engineID, paths: paths)

            #expect(second.root == first.root)
            #expect(exists(marker))
        }
    }

    @Test func installedFindsOnlyCompleteEngines() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            #expect(EngineInstaller.installed(id: engineID, paths: paths) == nil)

            // A folder with the right name but without the pieces is not an engine.
            try write("stale", to: paths.engines.appendingPathComponent("\(engineID)/stale.txt"))
            #expect(EngineInstaller.installed(id: engineID, paths: paths) == nil)

            _ = try EngineInstaller.install(
                template: try makeTemplateTar(in: dir), engine: try makeEngineTar(in: dir),
                id: engineID, paths: paths)
            #expect(EngineInstaller.installed(id: engineID, paths: paths)?.id == engineID)
        }
    }

    @Test func failedInstallKeepsPrevious() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let previous = try EngineInstaller.install(
                template: try makeTemplateTar(in: dir), engine: try makeEngineTar(in: dir),
                id: "previous", paths: paths)

            let corrupted = dir.appendingPathComponent("corrupted.tar.xz")
            try Data("this is not an xz archive".utf8).write(to: corrupted)
            #expect(throws: EngineError.self) {
                try EngineInstaller.install(
                    template: try makeTemplateTar(in: dir, name: "template2.tar.xz"), engine: corrupted,
                    id: engineID, paths: paths)
            }

            #expect(FileManager.default.isExecutableFile(atPath: previous.wineBin.path))
            #expect(try names(in: paths.engines) == ["previous"])
        }
    }

    @Test func failedReinstallKeepsExistingFolder() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let stale = paths.engines.appendingPathComponent("\(engineID)/stale.txt")
            try write("stale", to: stale)

            let corrupted = dir.appendingPathComponent("corrupted.tar.xz")
            try Data("this is not an xz archive".utf8).write(to: corrupted)
            #expect(throws: EngineError.self) {
                try EngineInstaller.install(
                    template: corrupted, engine: try makeEngineTar(in: dir), id: engineID, paths: paths)
            }

            #expect(exists(stale))
            #expect(try names(in: paths.engines) == [engineID])
        }
    }

    @Test func reinstallReplacesIncompleteFolder() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let stale = paths.engines.appendingPathComponent("\(engineID)/stale.txt")
            try write("stale", to: stale)

            let engine = try EngineInstaller.install(
                template: try makeTemplateTar(in: dir), engine: try makeEngineTar(in: dir),
                id: engineID, paths: paths)

            #expect(FileManager.default.isExecutableFile(atPath: engine.wineBin.path))
            #expect(!exists(stale))
            // The replaced folder is deleted, not left behind under a hidden name.
            #expect(try names(in: paths.engines) == [engineID])
        }
    }

    @Test func archiveWithoutWineIsRejected() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            #expect(throws: EngineError.self) {
                try EngineInstaller.install(
                    template: try makeTemplateTar(in: dir),
                    engine: try makeEngineTar(in: dir, withWine: false),
                    id: engineID, paths: paths)
            }
            let left = try names(in: paths.engines)
            #expect(left.isEmpty)
        }
    }

    @Test func archiveWithoutSingleRootIsRejected() throws {
        try withScratchDirectory { dir in
            let paths = makePaths(in: dir)
            let source = dir.appendingPathComponent("two-roots", isDirectory: true)
            try write("a", to: source.appendingPathComponent("first/file"))
            try write("b", to: source.appendingPathComponent("second/file"))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            let tar = dir.appendingPathComponent("two-roots.tar.xz")
            process.arguments = ["-cJf", tar.path, "-C", source.path, "first", "second"]
            try process.run()
            process.waitUntilExit()

            #expect(throws: EngineError.self) {
                try EngineInstaller.install(
                    template: try makeTemplateTar(in: dir), engine: tar, id: engineID, paths: paths)
            }
            let left = try names(in: paths.engines)
            #expect(left.isEmpty)
        }
    }
}

// MARK: - Artifact cache

@Suite("ArtifactStore")
struct ArtifactStoreTests {
    private static let content = Data("fake engine".utf8)

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func artifact(url: URL? = nil) -> Artifact {
        Artifact(file: "engine.tar.xz", sha256: hash(content), url: url)
    }

    /// Fails the test if the code tries to download.
    private static func noDownload(_ source: URL, _ destination: URL) async throws {
        Issue.record("unexpected download of \(source)")
    }

    @Test func sha256Hex() throws {
        try withScratchDirectory { dir in
            let file = dir.appendingPathComponent("file")
            try Self.content.write(to: file)
            #expect(try ArtifactStore.sha256Hex(of: file) == Self.hash(Self.content))
        }
    }

    @Test func ensuresFromLocalSource() async throws {
        try await withAsyncScratchDirectory { dir in
            let source = dir.appendingPathComponent("source", isDirectory: true)
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            try Self.content.write(to: source.fileCreatingDirectory("engine.tar.xz"))

            let path = try await ArtifactStore.ensure(
                Self.artifact(), cache: cache, localSources: [source], download: Self.noDownload)

            #expect(path.path == cache.appendingPathComponent("engine.tar.xz").path)
            #expect(try Data(contentsOf: path) == Self.content)
            #expect(try names(in: cache) == ["engine.tar.xz"])
        }
    }

    @Test func artifactHashMismatch() async throws {
        try await withAsyncScratchDirectory { dir in
            let source = dir.appendingPathComponent("source", isDirectory: true)
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            try Data("something else".utf8).write(to: source.fileCreatingDirectory("engine.tar.xz"))

            await #expect(throws: ArtifactError.self) {
                try await ArtifactStore.ensure(
                    Self.artifact(), cache: cache, localSources: [source], download: Self.noDownload)
            }

            // Neither the file nor its `.partial` stays in the cache.
            let left = try names(in: cache)
            #expect(left.isEmpty)
        }
    }

    @Test func missingArtifactListsWhereItLooked() async throws {
        try await withAsyncScratchDirectory { dir in
            let source = dir.appendingPathComponent("source", isDirectory: true)
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            let url = URL(string: "https://example.invalid/engine.tar.xz")!

            do {
                _ = try await ArtifactStore.ensure(
                    Self.artifact(url: url), cache: cache, localSources: [source],
                    download: { _, _ in })
                Issue.record("expected an error")
            } catch let error as ArtifactError {
                let message = error.localizedDescription
                #expect(message.contains("engine.tar.xz"))
                #expect(message.contains(source.appendingPathComponent("engine.tar.xz").path))
                #expect(message.contains(url.absoluteString))
            }
        }
    }

    @Test func alreadyInCacheDoesNotCopyOrDownload() async throws {
        try await withAsyncScratchDirectory { dir in
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            try Self.content.write(to: cache.fileCreatingDirectory("engine.tar.xz"))
            let url = URL(string: "https://example.invalid/engine.tar.xz")!

            let path = try await ArtifactStore.ensure(
                Self.artifact(url: url), cache: cache, localSources: [], download: Self.noDownload)

            #expect(path.path == cache.appendingPathComponent("engine.tar.xz").path)
        }
    }

    @Test func corruptedCacheIsRefetched() async throws {
        try await withAsyncScratchDirectory { dir in
            let source = dir.appendingPathComponent("source", isDirectory: true)
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            try Self.content.write(to: source.fileCreatingDirectory("engine.tar.xz"))
            try Data("half done".utf8).write(to: cache.fileCreatingDirectory("engine.tar.xz"))

            let path = try await ArtifactStore.ensure(
                Self.artifact(), cache: cache, localSources: [source], download: Self.noDownload)

            #expect(try Data(contentsOf: path) == Self.content)
        }
    }

    @Test func staleSecondSourceIsSkipped() async throws {
        try await withAsyncScratchDirectory { dir in
            let wrong = dir.appendingPathComponent("wrong", isDirectory: true)
            let right = dir.appendingPathComponent("right", isDirectory: true)
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            try Data("old version".utf8).write(to: wrong.fileCreatingDirectory("engine.tar.xz"))
            try Self.content.write(to: right.fileCreatingDirectory("engine.tar.xz"))

            let path = try await ArtifactStore.ensure(
                Self.artifact(), cache: cache, localSources: [wrong, right], download: Self.noDownload)

            #expect(try Data(contentsOf: path) == Self.content)
            #expect(try names(in: cache) == ["engine.tar.xz"])
        }
    }

    @Test func downloadsWhenNoLocalSource() async throws {
        try await withAsyncScratchDirectory { dir in
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            let url = URL(string: "https://example.invalid/engine.tar.xz")!
            var requested: [URL] = []
            var destinations: [String] = []

            let path = try await ArtifactStore.ensure(
                Self.artifact(url: url), cache: cache, localSources: [dir.appendingPathComponent("empty")],
                download: { source, destination in
                    requested.append(source)
                    destinations.append(destination.lastPathComponent)
                    try Self.content.write(to: destination)
                })

            #expect(requested == [url])
            // It downloads into `<file>.partial` and promotes it, never straight into the final name.
            #expect(destinations == ["engine.tar.xz.partial"])
            #expect(try Data(contentsOf: path) == Self.content)
            #expect(try names(in: cache) == ["engine.tar.xz"])
        }
    }

    @Test func downloadWithWrongHashIsRefused() async throws {
        try await withAsyncScratchDirectory { dir in
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            let url = URL(string: "https://example.invalid/engine.tar.xz")!

            await #expect(throws: ArtifactError.self) {
                try await ArtifactStore.ensure(
                    Self.artifact(url: url), cache: cache, localSources: [],
                    download: { _, destination in try Data("tampered".utf8).write(to: destination) })
            }

            let left = try names(in: cache)
            #expect(left.isEmpty)
        }
    }

    @Test func failedDownloadRemovesPartial() async throws {
        try await withAsyncScratchDirectory { dir in
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            let url = URL(string: "https://example.invalid/engine.tar.xz")!

            // The network error itself is reported, not hidden behind "not found".
            await #expect(throws: NetworkDown.self) {
                try await ArtifactStore.ensure(
                    Self.artifact(url: url), cache: cache, localSources: [],
                    download: { _, destination in
                        try Data("half".utf8).write(to: destination)
                        throw NetworkDown()
                    })
            }

            let left = try names(in: cache)
            #expect(left.isEmpty)
        }
    }

    @Test func staleLeftoverPartialIsOverwritten() async throws {
        try await withAsyncScratchDirectory { dir in
            let source = dir.appendingPathComponent("source", isDirectory: true)
            let cache = dir.appendingPathComponent("cache", isDirectory: true)
            try Self.content.write(to: source.fileCreatingDirectory("engine.tar.xz"))
            try Data("interrupted".utf8).write(to: cache.fileCreatingDirectory("engine.tar.xz.partial"))

            let path = try await ArtifactStore.ensure(
                Self.artifact(), cache: cache, localSources: [source], download: Self.noDownload)

            #expect(try Data(contentsOf: path) == Self.content)
            #expect(try names(in: cache) == ["engine.tar.xz"])
        }
    }
}

private extension URL {
    /// Creates this folder, then returns the path of `name` inside it, so a test can write a file in one expression.
    func fileCreatingDirectory(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return appendingPathComponent(name)
    }
}
