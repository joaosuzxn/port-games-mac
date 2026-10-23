import Darwin
import Foundation

/// An exclusive `flock` on a file, taken without blocking a thread: it polls until free. Held between
/// processes too (another launcher, the CLI and the app).
struct FileLock {
    let fd: Int32

    static func acquire(_ file: URL) async throws -> FileLock {
        let fd = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path]) }
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                close(fd)
                throw error
            }
        }
        return FileLock(fd: fd)
    }

    /// Closing the descriptor releases the lock.
    func release() { close(fd) }
}
