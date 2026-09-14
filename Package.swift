// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LaunchSet",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LaunchSetCore"),
        .executableTarget(name: "LaunchSet", dependencies: ["LaunchSetCore"]),
        .executableTarget(name: "SelfCheck", dependencies: ["LaunchSetCore"]),
        .executableTarget(name: "LaunchSetCLI", dependencies: ["LaunchSetCore"]),
    ]
)
