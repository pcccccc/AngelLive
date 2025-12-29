// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AngelLiveCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "AngelLiveCore",
            targets: ["AngelLiveCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pcccccc/LiveParse", from: "2.0.6"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/hyperoslo/Cache", from: "7.4.0")
    ],
    targets: [
        .target(
            name: "AngelLiveCore",
            dependencies: [
                "LiveParse",
                "Alamofire",
                .product(name: "Cache", package: "Cache")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "AngelLiveCoreTests",
            dependencies: ["AngelLiveCore"],
            path: "Tests"
        ),
    ]
)
