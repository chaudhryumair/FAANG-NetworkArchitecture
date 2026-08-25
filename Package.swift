// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkArchitecture",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "NetworkArchitecture",
            targets: ["NetworkArchitecture"]
        ),
    ],
    targets: [
        .target(
            name: "NetworkArchitecture",
            path: "Sources/NetworkArchitecture",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NetworkArchitectureTests",
            dependencies: ["NetworkArchitecture"],
            path: "Tests/NetworkArchitectureTests"
        ),
    ]
)
