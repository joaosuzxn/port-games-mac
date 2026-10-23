import Foundation

/// Graphics layer used to translate Direct3D.
public enum Renderer: String, Codable, Sendable {
    case wined3d, d9vk, dxvk, d3dmetal
}

/// A value written to the Wine registry: text (`REG_SZ`) or a 32-bit number (`REG_DWORD`).
///
/// In JSON a string is a `.string` and an integer from 0 to 4294967295 is a `.dword`;
/// anything else (negative, too large, fractional, boolean, null) fails to decode.
public enum RegistryValue: Codable, Equatable, Sendable {
    case string(String)
    case dword(UInt32)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let number = try? container.decode(UInt32.self) {
            self = .dword(number)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A registry value must be a string or an integer from 0 to 4294967295")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .dword(let number): try container.encode(number)
        }
    }
}

/// One registry key with the values to set on it.
public struct RegistryKey: Codable, Equatable, Sendable {
    public enum Hive: String, Codable, Sendable {
        case system, user
    }

    public var hive: Hive
    public var key: String
    public var values: [String: RegistryValue]

    public init(hive: Hive, key: String, values: [String: RegistryValue]) {
        self.hive = hive
        self.key = key
        self.values = values
    }
}

/// How to run one game: graphics layer, executable, Wine tweaks and registry settings.
public struct Recipe: Codable, Equatable, Sendable {
    public var appID: UInt32?
    public var renderer: Renderer
    /// Makes Wine's Mac driver emulate display mode changes (`EmulateModeset`).
    public var emulateModeset: Bool
    /// Volume label of the fake CD-ROM drive, for games that check for a disc.
    public var cdLabel: String?
    /// Executable to start, relative to the game folder; `nil` means "find it from the Steam data".
    public var executable: String?
    public var arguments: [String]
    public var environment: [String: String]
    public var dllOverrides: [String: String]
    public var registry: [RegistryKey]

    public init(
        appID: UInt32?,
        renderer: Renderer,
        emulateModeset: Bool,
        cdLabel: String?,
        executable: String?,
        arguments: [String],
        environment: [String: String],
        dllOverrides: [String: String],
        registry: [RegistryKey]
    ) {
        self.appID = appID
        self.renderer = renderer
        self.emulateModeset = emulateModeset
        self.cdLabel = cdLabel
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.registry = registry
    }

    private enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case renderer
        case emulateModeset = "emulate_modeset"
        case cdLabel = "cd_label"
        case executable
        case arguments
        case environment
        case dllOverrides = "dll_overrides"
        case registry
    }

    /// Used for games that have no recipe: WineD3D with display mode emulation, nothing else.
    public static let generic = Recipe(
        appID: nil, renderer: .wined3d, emulateModeset: true, cdLabel: nil,
        executable: nil, arguments: [], environment: [:], dllOverrides: [:], registry: [])
}

/// Finds the recipe for a game: a local one (`recipes/<appID>.json`) wins over the one bundled
/// with the app, which wins over `Recipe.generic`.
public struct RecipeStore {
    private let paths: Paths
    private let bundled: Bundle

    /// Uses the recipes shipped inside LauncherCore.
    public init(paths: Paths) {
        self.init(paths: paths, bundled: .module)
    }

    /// `bundled` is the bundle holding a `recipes/` folder with `<appID>.json` files.
    public init(paths: Paths, bundled: Bundle) {
        self.paths = paths
        self.bundled = bundled
    }

    /// Never fails: a local or bundled file that is missing or cannot be decoded is skipped,
    /// so a broken override cannot keep a game from starting.
    public func recipe(for appID: UInt32) -> Recipe {
        if let recipe = Self.decode(contentsOf: localURL(appID)) { return recipe }
        if let url = bundledURL(appID), let recipe = Self.decode(contentsOf: url) { return recipe }
        return .generic
    }

    /// Writes the local recipe, replacing the previous one. Atomic, so a crash never leaves a
    /// half-written file that would shadow the bundled recipe.
    public func saveLocal(_ recipe: Recipe, for appID: UInt32) throws {
        try FileManager.default.createDirectory(at: paths.recipes, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(recipe)
        try data.write(to: localURL(appID), options: .atomic)
    }

    public func hasBundled(_ appID: UInt32) -> Bool {
        bundledURL(appID) != nil
    }

    private func localURL(_ appID: UInt32) -> URL {
        paths.recipes.appendingPathComponent("\(appID).json", isDirectory: false)
    }

    private func bundledURL(_ appID: UInt32) -> URL? {
        bundled.url(forResource: String(appID), withExtension: "json", subdirectory: "recipes")
    }

    private static func decode(contentsOf url: URL) -> Recipe? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Recipe.self, from: data)
    }
}
