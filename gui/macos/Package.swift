// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Rawenv",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "RawenvLib",
            path: "Sources/Rawenv"
        ),
        .executableTarget(
            name: "Rawenv",
            dependencies: ["RawenvLib"],
            path: "Sources/RawenvApp",
            exclude: ["Assets.xcassets"],
            resources: [.copy("AppIcon.png")],
            swiftSettings: [.define("SPM_BUILD")]
        ),
        .testTarget(
            name: "RawenvUnitTests",
            dependencies: ["RawenvLib"],
            path: "Tests/RawenvUnitTests"
        ),
        .testTarget(
            name: "RawenvIntegrationTests",
            dependencies: ["RawenvLib"],
            path: "Tests/RawenvIntegrationTests"
        ),
        .testTarget(
            name: "RawenvE2ETests",
            dependencies: ["RawenvLib"],
            path: "Tests/RawenvE2ETests"
        ),
    ]
)
