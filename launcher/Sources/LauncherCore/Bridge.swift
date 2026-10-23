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
    ///
    /// The engine is shared: a game of another prefix may be running from it. So a file there is only
    /// replaced when its content changes, always by rename (a running game keeps the file it mapped),
    /// and only once it is final (the signature is removed before it is in place).
    public func stage(into engine: Engine, prefix: URL) throws {
        let data32 = try Data(contentsOf: dll32)
        let data64 = try Data(contentsOf: dll64)
        // Built and checked before anything is written: a bad bridge changes nothing.
        let forwarder32 = try PEForwarder.generate(from: data32, target: "lsteamclient")
        let forwarder64 = try PEForwarder.generate(from: data64, target: "lsteamclient")

        let wineLib = engine.root.appendingPathComponent("wine/lib/wine", isDirectory: true)
        // The build's ad-hoc signature no longer matches once Wine loads the library from here.
        try install(Data(contentsOf: unixLibrary), at: wineLib.appendingPathComponent("x86_64-unix/lsteamclient.so"),
            prepare: removeSignature)
        try install(data64, at: wineLib.appendingPathComponent("x86_64-windows/lsteamclient.dll"))
        try install(data32, at: wineLib.appendingPathComponent("i386-windows/lsteamclient.dll"))

        let windows = prefix.appendingPathComponent("drive_c/windows", isDirectory: true)
        try install(data64, at: windows.appendingPathComponent("system32/lsteamclient.dll"))
        try install(data32, at: windows.appendingPathComponent("syswow64/lsteamclient.dll"))

        let steam = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
        try install(forwarder32, at: steam.appendingPathComponent("steamclient.dll"))
        try install(forwarder64, at: steam.appendingPathComponent("bin64/steamclient.dll"))
        try install(forwarder64, at: steam.appendingPathComponent("steamclient64.dll"))
        try install(Data(contentsOf: steamStub), at: steam.appendingPathComponent("steam.exe"))
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

    /// Puts `data` at `target` unless it is already there: written to a temporary file next to it,
    /// `prepare`d there, compared, and renamed into place only if different.
    private func install(_ data: Data, at target: URL, prepare: ((URL) -> Void)? = nil) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString)")
        try data.write(to: temporary)
        defer { try? fileManager.removeItem(at: temporary) }
        prepare?(temporary)
        if let current = try? Data(contentsOf: target), current == (try Data(contentsOf: temporary)) { return }
        guard rename(temporary.path, target.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    private func removeSignature(_ file: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--remove-signature", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Not fatal: an unsigned file has nothing to remove, and the Python spike ignored it too.
        try? process.runAndWait()
    }
}
