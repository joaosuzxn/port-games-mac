import Darwin
import Foundation

/// The Mac's Steam client, which games reach through the bridge. A protocol so the launcher can be
/// tested without it.
public protocol SteamClientProbe: Sendable {
    func isRunning() -> Bool
    func open() throws
    func isLoggedIn() -> Bool
}

public struct SystemSteamClient: SteamClientProbe {
    let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// A process whose executable is `steam_osx`.
    public func isRunning() -> Bool {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return pids.prefix(Int(max(count, 0))).contains { pid in
            pid > 0 && ProcessTable.executablePath(of: pid).map { ($0 as NSString).lastPathComponent == "steam_osx" } == true
        }
    }

    /// `open -ga Steam`: in the background, without taking focus.
    public func open() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-ga", "Steam"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.runAndWait()
    }

    /// Running, and its connection log says it is logged on. (`loginusers.vdf` has no reliable marker:
    /// on this Mac it carries no `MostRecent`, and `registry.vdf` no `ActiveUser`.)
    public func isLoggedIn() -> Bool {
        isRunning() && connectionLogSaysLoggedOn()
    }

    /// Steam starts a new `logs/connection_log.txt` each time it opens (the old one becomes
    /// `.previous`), so its last state is the current session's.
    func connectionLogSaysLoggedOn() -> Bool {
        let file = home.appendingPathComponent("Library/Application Support/Steam/logs/connection_log.txt")
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        // The end is enough: the last state line is what counts.
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        let tail = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        return Self.isLoggedOn(connectionLog: tail)
    }

    /// The state of the last line that has one: `[time] [Logged On, 4, 7] …`.
    static func isLoggedOn(connectionLog: String) -> Bool {
        for line in connectionLog.split(whereSeparator: \.isNewline).reversed() {
            if let match = line.firstMatch(of: #/^\[[^\]]*\] \[([A-Za-z ]+), -?\d+, -?\d+\]/#) {
                return match.1 == "Logged On"
            }
        }
        return false
    }
}
