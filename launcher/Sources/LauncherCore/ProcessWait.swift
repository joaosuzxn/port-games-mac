import Foundation

extension Process {
    /// Starts the process and blocks the current thread until it ends.
    ///
    /// Waits on a semaphore that `terminationHandler` (Foundation's own queue) signals, not with
    /// `waitUntilExit()`: that one spins the run loop and, on a Swift concurrency thread, sometimes never
    /// returned. Async code should prefer `DepotDownloader.exit(of:)`, which blocks no thread.
    func runAndWait() throws {
        let done = DispatchSemaphore(value: 0)
        terminationHandler = { _ in done.signal() }
        do {
            try run()
        } catch {
            terminationHandler = nil
            throw error
        }
        done.wait()
    }
}
