// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NordDockerProxy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NordDockerProxy", path: "Sources/NordDockerProxy"),
    ]
)
