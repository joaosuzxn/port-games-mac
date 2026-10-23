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

    /// Running, with an account marked as the most recent login (`config/loginusers.vdf`).
    public func isLoggedIn() -> Bool {
        let file = home.appendingPathComponent("Library/Application Support/Steam/config/loginusers.vdf")
        guard isRunning(), let text = try? String(contentsOf: file, encoding: .utf8) else { return false }
        return text.contains(#/"MostRecent"\s+"1"/#)
    }
}
