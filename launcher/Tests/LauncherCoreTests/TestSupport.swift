import Foundation

/// Creates a unique temporary directory and removes it when the body returns.
///
/// Shared by test files added after the first two. Those keep their own private `withTemporaryDirectory`,
/// so this one has another name: a second function with the same signature would not compile.
func withScratchDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("launcher-core-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}
