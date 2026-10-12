// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HueBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HueBar",
            path: "Sources/HueBar"
        ),
        .testTarget(
            name: "HueBarTests",
            dependencies: ["HueBar"],
            path: "Tests/HueBarTests"
        ),
    ]
)
