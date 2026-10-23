import Foundation

public enum BridgeError: Error, LocalizedError, Equatable {
    /// A file of the bridge is not in `bridge/<engineID>/`.
    case missing(file: String)

    public var errorDescription: String? {
        switch self {
        case .missing(let file):
            return "the Steam bridge is not installed (missing \(file)); "
                + "build and publish it with spikes/steam-bridge/build_bridge.sh"
        }
    }
}

/// The `lsteamclient` bridge: lets a Windows game talk to the Mac's Steam client.
///
/// Its files (Steamworks SDK license: never in git, never shipped) are built by the owner with
/// `spikes/steam-bridge/build_bridge.sh`, which publishes them to `bridge/<engineID>/`:
/// ```
/// lsteamclient.so                   Mac side, loaded by Wine
/// i386-windows/lsteamclient.dll     Windows side, 32-bit
/// x86_64-windows/lsteamclient.dll   Windows side, 64-bit
/// steam.exe                         stub that tells games Steam is running
/// ```
/// The layout it is staged into comes from Neutron (https://github.com/mont127/Neutron, Apache-2.0).
public struct Bridge: Sendable {
    public let folder: URL

    var unixLibrary: URL { folder.appendingPathComponent("lsteamclient.so") }
    var dll32: URL { folder.appendingPathComponent("i386-windows/lsteamclient.dll") }
    var dll64: URL { folder.appendingPathComponent("x86_64-windows/lsteamclient.dll") }
    var steamStub: URL { folder.appendingPathComponent("steam.exe") }

    /// Throws `BridgeError.missing` if any of the bridge's files is not there.
    public init(paths: Paths, engineID: String) throws {
        folder = paths.bridge.appendingPathComponent(engineID, isDirectory: true)
        for file in [unixLibrary, dll32, dll64, steamStub]
        where !FileManager.default.fileExists(atPath: file.path) {
            throw BridgeError.missing(file: file.path)
        }
    }

    /// Copies the bridge into the engine's Wine and into the prefix, and writes the `steamclient`
    /// forwarders and `steam.exe` where games look for Steam. **The prefix's Wine must be stopped.**
    public func stage(into engine: Engine, prefix: URL) throws {
        let wineLib = engine.root.appendingPathComponent("wine/lib/wine", isDirectory: true)
        let unixTarget = wineLib.appendingPathComponent("x86_64-unix/lsteamclient.so")
        try copy(unixLibrary, to: unixTarget)
        // The copy keeps the build's ad-hoc signature, which no longer matches once Wine loads it here.
        removeSignature(unixTarget)
        try copy(dll64, to: wineLib.appendingPathComponent("x86_64-windows/lsteamclient.dll"))
        try copy(dll32, to: wineLib.appendingPathComponent("i386-windows/lsteamclient.dll"))

        let windows = prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
        try copy(dll64, to: windows.appendingPathComponent("system32/lsteamclient.dll"))
        try copy(dll32, to: windows.appendingPathComponent("syswow64/lsteamclient.dll"))

        let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        let forwarder32 = try PEForwarder.generate(from: Data(contentsOf: dll32), target: "lsteamclient")
        let forwarder64 = try PEForwarder.generate(from: Data(contentsOf: dll64), target: "lsteamclient")
        try write(forwarder32, to: steam.appendingPathComponent("steamclient.dll"))
        try write(forwarder64, to: steam.appendingPathComponent("bin64/steamclient.dll"))
        try write(forwarder64, to: steam.appendingPathComponent("steamclient64.dll"))
        try copy(steamStub, to: steam.appendingPathComponent("steam.exe"))
    }

    /// What a game needs to find the Mac's Steam through the bridge.
    public static func environment(
        appID: UInt32, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        [
            "SteamAppId": String(appID),
            "SteamGameId": String(appID),
            "STEAM_COMPAT_CLIENT_INSTALL_PATH": home.standardizedFileURL.path
                + "/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS",
        ]
    }

    private func copy(_ source: URL, to target: URL) throws {
        try write(Data(contentsOf: source), to: target)
    }

    /// Atomic (temporary file + rename), so a Wine that starts meanwhile never loads half a file.
    private func write(_ data: Data, to target: URL) throws {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    private func removeSignature(_ file: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--remove-signature", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Not fatal: an unsigned file has nothing to remove, and the Python spike ignored it too.
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}
