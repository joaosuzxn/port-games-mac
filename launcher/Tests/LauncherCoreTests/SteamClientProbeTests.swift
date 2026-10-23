import Foundation
import Testing
@testable import LauncherCore

/// Lines in the shape of Steam for Mac's `logs/connection_log.txt` (2026-10-23).
private let loggingOn = """
    [2026-10-23 10:52:45] [Logged Off, 0, 0] [U:1:1] CCMInterface::SetSteamID( [U:1:1] )
    [2026-10-23 10:52:45] Connectivity test: result=Connected (since 0.0s ago), prev=Unknown, in progress=0
    [2026-10-23 10:52:46] [Logged Off, 4, 0] [U:1:1] LogOn() called; not connected yet, scheduling connection.
    [2026-10-23 10:52:47] [Connected, 4, 7] [U:1:1] Logging on [U:1:1]
    """

private let loggedOn = loggingOn + """

    [2026-10-23 10:52:48] [Logging On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : [U:1:1] 'OK'
    [2026-10-23 10:52:48] [Logged On, 4, 7] [U:1:1] RecvMsgClientLogOnResponse() : processing complete
    [2026-10-23 10:53:10] Connectivity test: result=Connected (since 24.5s ago), prev=Failed, in progress=0
    """

@Suite("Steam for Mac login state")
struct SteamClientProbeTests {
    @Test func loggedOnAfterTheLogOnResponse() {
        #expect(SystemSteamClient.isLoggedOn(connectionLog: loggedOn))
    }

    @Test func notWhileLoggingOn() {
        #expect(!SystemSteamClient.isLoggedOn(connectionLog: loggingOn))
    }

    @Test func notAfterLogOff() {
        let off = loggedOn + "\n[2026-10-23 11:00:00] [Logged Off, 0, 0] [U:1:1] LogOff()\n"
        #expect(!SystemSteamClient.isLoggedOn(connectionLog: off))
    }

    /// The real file has Windows line endings, and a CR-LF pair is one Character in Swift.
    @Test func windowsLineEndings() {
        #expect(SystemSteamClient.isLoggedOn(connectionLog: loggedOn.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"))
    }

    @Test func notWithoutLog() {
        #expect(!SystemSteamClient.isLoggedOn(connectionLog: ""))
    }

    @Test func readsTheLogUnderHome() throws {
        try withScratchDirectory { home in
            let log = home.appendingPathComponent("Library/Application Support/Steam/logs/connection_log.txt")
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(loggedOn.utf8).write(to: log)
            #expect(SystemSteamClient(home: home).connectionLogSaysLoggedOn())
        }
    }
}

/// The owner's Steam for Mac, open and logged in (run with Steam in that state).
@Suite("Steam for Mac login state (real)", .enabled(if: ProcessInfo.processInfo.environment["PORTGAMES_INTEGRATION"] == "1"))
struct RealSteamClientProbeTests {
    @Test func realSteamIsRunningAndLoggedIn() {
        let steam = SystemSteamClient()
        #expect(steam.isRunning())
        #expect(steam.isLoggedIn())
    }
}
