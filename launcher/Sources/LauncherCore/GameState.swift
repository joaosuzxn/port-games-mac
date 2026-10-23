import Foundation

/// Install state of one game, persisted as `state/<appID>.json`.
public struct GameState: Codable, Equatable, Sendable {
    public var appID: UInt32
    /// Steam's `installdir` for the app (folder name inside the game directory).
    public var installDir: String
    public var buildID: UInt64
    /// Manifest ID installed for each depot ID.
    public var depotManifests: [UInt32: UInt64]
    public var installedAt: Date
    /// `false` while a download is in progress or was interrupted.
    public var complete: Bool

    public init(
        appID: UInt32,
        installDir: String,
        buildID: UInt64,
        depotManifests: [UInt32: UInt64],
        installedAt: Date,
        complete: Bool
    ) {
        self.appID = appID
        self.installDir = installDir
        self.buildID = buildID
        self.depotManifests = depotManifests
        self.installedAt = installedAt
        self.complete = complete
    }

    private enum CodingKeys: String, CodingKey {
        case appID, installDir, buildID, depotManifests, installedAt, complete
    }

    // `JSONEncoder` writes dictionaries whose keys are not `String`/`Int` as a flat
    // `[key, value, key, value]` array. Depot IDs are written as decimal string keys instead,
    // so the file stays a readable JSON object.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appID = try container.decode(UInt32.self, forKey: .appID)
        installDir = try container.decode(String.self, forKey: .installDir)
        buildID = try container.decode(UInt64.self, forKey: .buildID)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        complete = try container.decode(Bool.self, forKey: .complete)

        let manifests = try container.decode([String: UInt64].self, forKey: .depotManifests)
        depotManifests = [:]
        for (depot, manifest) in manifests {
            guard let depotID = UInt32(depot) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .depotManifests, in: container,
                    debugDescription: "Depot ID \"\(depot)\" is not an unsigned 32-bit integer")
            }
            depotManifests[depotID] = manifest
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appID, forKey: .appID)
        try container.encode(installDir, forKey: .installDir)
        try container.encode(buildID, forKey: .buildID)
        try container.encode(installedAt, forKey: .installedAt)
        try container.encode(complete, forKey: .complete)
        let manifests = Dictionary(uniqueKeysWithValues: depotManifests.map { (String($0.key), $0.value) })
        try container.encode(manifests, forKey: .depotManifests)
    }
}

/// Reads and writes `GameState` files under `Paths.state`.
public enum GameStateStore {
    /// Returns `nil` when the game has no state file; throws when the file exists but is unreadable.
    public static func load(_ appID: UInt32, paths: Paths) throws -> GameState? {
        let data: Data
        do {
            data = try Data(contentsOf: paths.stateFile(appID))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        return try JSONDecoder().decode(GameState.self, from: data)
    }

    /// Writes atomically: Foundation writes a temporary file next to the target and renames it
    /// over it, so a crash never leaves a half-written state.
    public static func save(_ state: GameState, paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: paths.stateFile(state.appID), options: .atomic)
    }
}
