import CryptoKit
import Foundation

/// A third-party file (the wrapper template, the Wine engine) kept in a cache and checked by SHA-256.
public struct Artifact: Sendable, Equatable {
    /// File name, both in the cache and in each local source.
    public var file: String
    /// Expected SHA-256, as hexadecimal text.
    public var sha256: String
    /// Where to download it when no local source has it.
    public var url: URL?

    public init(file: String, sha256: String, url: URL?) {
        self.file = file
        self.sha256 = sha256
        self.url = url
    }
}

public enum ArtifactError: Error, LocalizedError, Equatable {
    /// No source had the file with the expected SHA-256. `searched` lists every place tried.
    case notFound(file: String, searched: [String])
    /// The download server answered with something other than success.
    case httpStatus(url: URL, code: Int)

    public var errorDescription: String? {
        switch self {
        case .notFound(let file, let searched):
            let places = searched.isEmpty ? "no sources" : searched.joined(separator: ", ")
            return "artifact \(file) not found with the expected SHA-256. Searched in: \(places)"
        case .httpStatus(let url, let code):
            return "download of \(url.absoluteString) failed with HTTP status \(code)"
        }
    }
}

/// Keeps artifacts in a cache folder. Port of `ensure_artifact` in `tools/builder/artifacts.py`.
public enum ArtifactStore {
    /// Returns the cached file for `artifact`, getting it first if needed.
    ///
    /// Order: the cache (a file there with the wrong hash is deleted), then each local source,
    /// then `artifact.url` through `download`. Every candidate is copied or downloaded to
    /// `<file>.partial` and renamed over the final name only after its SHA-256 matches, so the cache
    /// never holds a half-written or wrong file. The `.partial` file is removed on any failure.
    ///
    /// - Parameter download: called with the source URL and the file to write; the real one is
    ///   `downloadWithURLSession`, tests pass their own so they never touch the network.
    ///   Its errors are rethrown as they are.
    public static func ensure(
        _ artifact: Artifact,
        cache: URL,
        localSources: [URL],
        download: (URL, URL) async throws -> Void = ArtifactStore.downloadWithURLSession
    ) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        let target = cache.appendingPathComponent(artifact.file, isDirectory: false)
        let partial = cache.appendingPathComponent(artifact.file + ".partial", isDirectory: false)
        let expected = artifact.sha256.lowercased()

        if fileManager.fileExists(atPath: target.path) {
            if try sha256Hex(of: target) == expected { return target }
            try fileManager.removeItem(at: target)
        }

        var searched: [String] = []
        for source in localSources {
            let candidate = source.appendingPathComponent(artifact.file, isDirectory: false)
            searched.append(candidate.path)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else { continue }
            let promoted = try await promote(partial: partial, to: target, expected: expected) {
                try fileManager.copyItem(at: candidate, to: partial)
            }
            if promoted { return target }
        }

        if let url = artifact.url {
            searched.append(url.absoluteString)
            let promoted = try await promote(partial: partial, to: target, expected: expected) {
                try await download(url, partial)
            }
            if promoted { return target }
        }

        throw ArtifactError.notFound(file: artifact.file, searched: searched)
    }

    /// Runs `fill` to produce `partial`, then renames it to `target` if its hash is `expected`.
    /// Returns `false` (and leaves nothing behind) when the file is missing or its hash differs.
    private static func promote(
        partial: URL, to target: URL, expected: String, fill: () async throws -> Void
    ) async throws -> Bool {
        let fileManager = FileManager.default
        // A `.partial` left by an interrupted run would make the copy fail; start clean.
        try? fileManager.removeItem(at: partial)
        // Runs on every exit; after a successful rename there is nothing left to remove.
        defer { try? fileManager.removeItem(at: partial) }
        try await fill()
        // No file at all (a download that wrote nothing) counts like a wrong hash.
        guard fileManager.fileExists(atPath: partial.path), try sha256Hex(of: partial) == expected else {
            return false
        }
        try fileManager.moveItem(at: partial, to: target)
        return true
    }

    /// SHA-256 of a file as lowercase hexadecimal, read in 1 MiB blocks (the artifacts are large).
    public static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        // `read(upToCount:)` returns autoreleased buffers; without draining a pool on each pass they
        // all stay alive until the loop ends (about the whole file in memory for a 1 GiB archive).
        var more = true
        while more {
            try autoreleasepool {
                if let block = try handle.read(upToCount: 1 << 20), !block.isEmpty {
                    hasher.update(data: block)
                } else {
                    more = false
                }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Real download with `URLSession`: fetches `source` and moves the result to `destination`.
    /// Not covered by the unit tests (it needs the network).
    public static func downloadWithURLSession(_ source: URL, _ destination: URL) async throws {
        let (temporary, response) = try await URLSession.shared.download(from: source)
        let fileManager = FileManager.default
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? fileManager.removeItem(at: temporary)
            throw ArtifactError.httpStatus(url: source, code: http.statusCode)
        }
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
    }
}
