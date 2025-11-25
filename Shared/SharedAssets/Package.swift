// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SharedAssets",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "SharedAssets",
            targets: ["SharedAssets"]
        )
    ],
    targets: [
        .target(
            name: "SharedAssets",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
