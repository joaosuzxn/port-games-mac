import Foundation

/// A `launcherctl` command, parsed.
public enum Command: Equatable, Sendable {
    case login
    case logout
    case library
    case install(appID: UInt32, library: URL?)
    case update(UInt32)
    case uninstall(UInt32)
    case play(UInt32)
    /// Stops the game's Wine (a game left running).
    case stop(UInt32)
    case status(UInt32)
    /// Test mode: edits the game's local recipe, starting from the effective one.
    case recipe(appID: UInt32, edits: RecipeEdits)
}

/// Changes `launcherctl recipe` makes to the effective recipe; anything not given stays as it was.
public struct RecipeEdits: Equatable, Sendable {
    public var renderer: Renderer?
    public var emulateModeset: Bool?
    public var environment: [String: String]
    public var dllOverrides: [String: String]
    /// Only print the effective recipe.
    public var show: Bool

    public init(
        renderer: Renderer? = nil, emulateModeset: Bool? = nil, environment: [String: String] = [:],
        dllOverrides: [String: String] = [:], show: Bool = false
    ) {
        self.renderer = renderer
        self.emulateModeset = emulateModeset
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.show = show
    }

    public var isEmpty: Bool { renderer == nil && emulateModeset == nil && environment.isEmpty && dllOverrides.isEmpty }

    public func applied(to recipe: Recipe) -> Recipe {
        var out = recipe
        if let renderer { out.renderer = renderer }
        if let emulateModeset { out.emulateModeset = emulateModeset }
        out.environment.merge(environment) { _, new in new }
        out.dllOverrides.merge(dllOverrides) { _, new in new }
        return out
    }
}

public struct CLIError: Error, LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message + "\n\n" + CLI.usage }
}

public enum CLI {
    public static let usage = """
        usage:
          launcherctl login                         log in to Steam with a QR code (once per Mac)
          launcherctl logout                        forget the Steam login
          launcherctl library                       list the games of the account
          launcherctl install <appid> [--library DIR]   download the Windows version
          launcherctl update <appid>                download the current build over the installed one
          launcherctl uninstall <appid>             delete the game files (saves and recipe stay)
          launcherctl play <appid>                  open the game (Steam for Mac must be logged in)
          launcherctl stop <appid>                  stop a game left running
          launcherctl status <appid>                install state and effective recipe
          launcherctl recipe <appid> [--renderer wined3d|d9vk|dxvk|d3dmetal] [--emulate-modeset on|off]
                                     [--env KEY=VALUE]... [--dll NAME=VALUE]... [--show]
                                                    test mode: change the game's local recipe
        """

    public static func parse(_ arguments: [String]) throws -> Command {
        guard let command = arguments.first else { throw CLIError(message: "no command given") }
        var rest = Array(arguments.dropFirst())
        switch command {
        case "login", "logout", "library":
            guard rest.isEmpty else { throw CLIError(message: "\(command) takes no arguments") }
            return command == "login" ? .login : command == "logout" ? .logout : .library
        case "update", "uninstall", "play", "stop", "status":
            let appID = try takeAppID(&rest, command)
            guard rest.isEmpty else { throw CLIError(message: "unexpected arguments: \(rest.joined(separator: " "))") }
            switch command {
            case "update": return .update(appID)
            case "uninstall": return .uninstall(appID)
            case "play": return .play(appID)
            case "stop": return .stop(appID)
            default: return .status(appID)
            }
        case "install":
            let appID = try takeAppID(&rest, command)
            var library: URL?
            while !rest.isEmpty {
                let option = rest.removeFirst()
                guard option == "--library" else { throw CLIError(message: "unknown option \(option)") }
                library = URL(fileURLWithPath: try takeValue(&rest, option), isDirectory: true)
            }
            return .install(appID: appID, library: library)
        case "recipe":
            let appID = try takeAppID(&rest, command)
            var edits = RecipeEdits()
            while !rest.isEmpty {
                let option = rest.removeFirst()
                switch option {
                case "--show":
                    edits.show = true
                case "--renderer":
                    let value = try takeValue(&rest, option)
                    guard let renderer = Renderer(rawValue: value) else { throw CLIError(message: "unknown renderer \(value)") }
                    edits.renderer = renderer
                case "--emulate-modeset":
                    let value = try takeValue(&rest, option)
                    guard value == "on" || value == "off" else { throw CLIError(message: "--emulate-modeset takes on or off") }
                    edits.emulateModeset = value == "on"
                case "--env":
                    let (key, value) = try pair(try takeValue(&rest, option), option)
                    edits.environment[key] = value
                case "--dll":
                    let (key, value) = try pair(try takeValue(&rest, option), option)
                    edits.dllOverrides[key] = value
                default:
                    throw CLIError(message: "unknown option \(option)")
                }
            }
            return .recipe(appID: appID, edits: edits)
        default:
            throw CLIError(message: "unknown command \(command)")
        }
    }

    private static func takeAppID(_ rest: inout [String], _ command: String) throws -> UInt32 {
        guard !rest.isEmpty, let appID = UInt32(rest.removeFirst()) else {
            throw CLIError(message: "\(command) needs a Steam app ID (a number, e.g. 331160)")
        }
        return appID
    }

    private static func takeValue(_ rest: inout [String], _ option: String) throws -> String {
        guard !rest.isEmpty else { throw CLIError(message: "\(option) needs a value") }
        return rest.removeFirst()
    }

    /// `KEY=VALUE`, with a non-empty key.
    private static func pair(_ text: String, _ option: String) throws -> (String, String) {
        guard let equals = text.firstIndex(of: "="), equals != text.startIndex else {
            throw CLIError(message: "\(option) takes KEY=VALUE")
        }
        return (String(text[..<equals]), String(text[text.index(after: equals)...]))
    }
}
