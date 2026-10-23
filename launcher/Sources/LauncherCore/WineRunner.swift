import Darwin
import Foundation

/// Runs Wine for one prefix. A protocol so the prefix and game code can be tested with a fake.
public protocol WineRunning: Sendable {
    func run(_ args: [String], env: [String: String], cwd: URL?) async throws -> Int32
    func spawn(_ args: [String], env: [String: String], cwd: URL?) async throws -> Process
    func stop(timeout: Duration) async throws
}

public enum WineRunnerError: Error, LocalizedError, Equatable {
    /// The prefix's wineserver was sent SIGKILL and still holds its lock.
    case wineserverDidNotStop(prefix: String, pid: Int32)
    /// The prefix's wineserver is not from this engine (another Wine app uses the prefix); left running.
    case foreignWineserver(prefix: String, pid: Int32)

    public var errorDescription: String? {
        switch self {
        case .wineserverDidNotStop(let prefix, let pid):
            return "the wineserver of \(prefix) (PID \(pid)) did not stop, even after SIGKILL"
        case .foreignWineserver(let prefix, let pid):
            return "the wineserver of \(prefix) (PID \(pid)) belongs to another Wine installation; "
                + "quit the app that uses it and try again"
        }
    }
}

/// Runs `wine` from an engine against one prefix, with stdout and stderr appended to a log file.
public actor WineRunner: WineRunning {
    public nonisolated let engine: Engine
    public nonisolated let prefix: URL
    public nonisolated let log: URL
    /// Where wineserver keeps its per-prefix folders (`/tmp/.wine-<uid>`); tests use their own.
    private let serverRoot: URL

    public init(engine: Engine, prefix: URL, log: URL) {
        self.init(engine: engine, prefix: prefix, log: log, serverRoot: WineServerLock.defaultRoot)
    }

    init(engine: Engine, prefix: URL, log: URL, serverRoot: URL) {
        self.engine = engine
        self.prefix = prefix
        self.log = log
        self.serverRoot = serverRoot
    }

    /// Runs `wine <args>` and returns its exit status. `env` goes over the launcher's own environment.
    /// Cancelling the task terminates the process and throws `CancellationError`.
    public func run(_ args: [String], env: [String: String], cwd: URL?) async throws -> Int32 {
        try Task.checkCancellation()
        let process = try makeProcess(engine.wineBin, args, env: env, cwd: cwd, header: "wine")
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try launch(process)
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                // A cancel that came before the launch found nothing to terminate.
                if Task.isCancelled { process.terminate() }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        return status
    }

    /// Starts `wine <args>` and returns it running; the caller waits for it or terminates it.
    public func spawn(_ args: [String], env: [String: String], cwd: URL?) throws -> Process {
        let process = try makeProcess(engine.wineBin, args, env: env, cwd: cwd, header: "wine")
        try launch(process)
        return process
    }

    /// Stops every Wine process of the prefix: `wineserver -k`, then waits up to `timeout` for the
    /// prefix's wineserver to release its lock. After that it sends SIGKILL to the server, but only
    /// if its executable is inside this engine.
    public func stop(timeout: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let env = WineEnvironment.make(engine: engine, prefix: prefix, recipe: .generic)
        let killer = try makeProcess(engine.wineserver, ["-k"], env: env, cwd: nil, header: "wineserver")
        try launch(killer)
        // A `-k` that hangs must not outlive this call.
        defer { if killer.isRunning { kill(killer.processIdentifier, SIGKILL) } }

        while ContinuousClock.now < deadline {
            if server() == nil, !killer.isRunning { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let pid = server() else { return }
        guard ProcessTable.executable(of: pid, isInside: engine.root) else {
            throw WineRunnerError.foreignWineserver(prefix: prefix.path, pid: pid)
        }

        appendToLog("SIGKILL wineserver \(pid): still running \(timeout) after wineserver -k\n")
        kill(pid, SIGKILL)
        let killDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while server() == pid, ContinuousClock.now < killDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if server() == pid { throw WineRunnerError.wineserverDidNotStop(prefix: prefix.path, pid: pid) }
    }

    private func server() -> pid_t? { WineServerLock.holder(prefix: prefix, serverRoot: serverRoot) }

    /// A process for `executable` with its output appended to the log, after a line naming the command.
    private func makeProcess(
        _ executable: URL, _ args: [String], env: [String: String], cwd: URL?, header: String
    ) throws -> Process {
        let output = try openLog()
        output.write(Data("[\(Date().ISO8601Format())] \(([header] + args).joined(separator: " "))\n".utf8))
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(env) { _, new in new }
        process.currentDirectoryURL = cwd
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        return process
    }

    /// Launches and closes this side of the log: the child keeps its own copy.
    private func launch(_ process: Process) throws {
        defer { (process.standardOutput as? FileHandle)?.closeFile() }
        try process.run()
    }

    private func appendToLog(_ text: String) {
        guard let output = try? openLog() else { return }
        output.write(Data(text.utf8))
        output.closeFile()
    }

    /// Opened with O_APPEND: Wine, wineserver and the game may write to the same log at once.
    private func openLog() throws -> FileHandle {
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(log.path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: log.path]) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}

/// How wineserver marks that it serves a prefix: `<root>/server-<dev>-<inode>/lock`, with a write lock
/// (fcntl) on its first byte for as long as it runs. `dev` and `inode` are those of the prefix folder.
enum WineServerLock {
    static var defaultRoot: URL { URL(fileURLWithPath: "/tmp/.wine-\(getuid())", isDirectory: true) }

    static func directoryName(device: dev_t, inode: ino_t) -> String {
        "server-\(String(UInt32(bitPattern: device), radix: 16))-\(String(inode, radix: 16))"
    }

    /// `nil` when the prefix folder does not exist.
    static func lockFile(prefix: URL, serverRoot: URL) -> URL? {
        var info = stat()
        guard stat(prefix.path, &info) == 0 else { return nil }
        return serverRoot
            .appendingPathComponent(directoryName(device: info.st_dev, inode: info.st_ino), isDirectory: true)
            .appendingPathComponent("lock", isDirectory: false)
    }

    /// PID of the wineserver serving the prefix, or `nil` if none.
    static func holder(prefix: URL, serverRoot: URL) -> pid_t? {
        guard let lock = lockFile(prefix: prefix, serverRoot: serverRoot) else { return nil }
        let fd = open(lock.path, O_RDWR | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var query = flock()
        query.l_start = 0
        query.l_len = 1
        query.l_type = Int16(F_WRLCK)
        query.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_GETLK, &query) == 0, query.l_type != Int16(F_UNLCK) else { return nil }
        return query.l_pid
    }
}

enum ProcessTable {
    static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Compares resolved paths, so `/var/…` and `/private/var/…` match.
    static func executable(of pid: pid_t, isInside folder: URL) -> Bool {
        guard let executable = executablePath(of: pid).flatMap(realPath),
            let folder = realPath(folder.path)
        else { return false }
        return executable.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
