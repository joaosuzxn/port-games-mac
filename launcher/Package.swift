// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Launcher",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
        .executable(name: "launcherctl", targets: ["launcherctl"]),
    ],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "launcherctl", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
    ]
)
