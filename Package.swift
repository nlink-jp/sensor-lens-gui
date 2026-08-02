// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SensorLens",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SensorLens",
            path: "Sources/SensorLens"
        ),
        .testTarget(
            name: "SensorLensTests",
            dependencies: ["SensorLens"],
            path: "Tests/SensorLensTests"
        ),
    ]
)
