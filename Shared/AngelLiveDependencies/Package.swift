// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AngelLiveDependencies",
    platforms: [
        .iOS(.v18),
        .macOS(.v11),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "AngelLiveDependencies",
            targets: ["AngelLiveDependencies"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pcccccc/AcknowList", branch: "main"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
        .package(url: "https://github.com/bugsnag/bugsnag-cocoa", from: "6.34.0"),
        .package(url: "https://github.com/hyperoslo/Cache", from: "7.4.0"),
        .package(url: "https://github.com/Lakr233/ColorfulX", from: "5.2.8"),
        .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket", from: "7.6.5"),
        .package(url: "https://github.com/1024jp/GzipSwift", from: "6.1.0"),
        .package(url: "https://github.com/johnno1962/InjectionNext", from: "1.4.3"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "8.6.0"),
        .package(url: "https://github.com/yeatse/KingfisherWebP.git", from: "1.7.0"),
        .package(url: "https://github.com/TracyPlayer/KSPlayer", exact: "2.6.2"),
        .package(url: "https://github.com/pcccccc/LiveParse", from: "1.9.1"),
        .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.5"),
        .package(url: "https://github.com/sanzaru/SimpleToast", from: "0.11.0"),
        .package(url: "https://github.com/daltoniam/Starscream", from: "4.0.8"),
        .package(url: "https://github.com/tsolomko/SWCompression", from: "4.8.6"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.86.2"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.32.0"),
        .package(url: "https://github.com/markiv/SwiftUI-Shimmer", branch: "iOS17-animate-start-end-points"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.2"),
        .package(url: "https://github.com/gunterhager/UDPBroadcastConnection", from: "5.0.5"),
        .package(url: "https://github.com/sunghyun-k/swiftui-toasts", from: "1.1.1")
    ],
    targets: [
        .target(
            name: "AngelLiveDependencies",
            dependencies: [
                "Alamofire",
                .product(name: "Cache", package: "Cache"),
                "LiveParse",
                "Starscream",
                "SwiftyJSON",
                "SWCompression",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftProtobufPluginLibrary", package: "swift-protobuf"),
                .product(name: "protoc-gen-swift", package: "swift-protobuf"),
                .product(name: "Gzip", package: "GzipSwift"),
                .product(name: "Shimmer", package: "SwiftUI-Shimmer"),
                "AcknowList",
                .product(name: "UDPBroadcast", package: "UDPBroadcastConnection"),
                "CocoaAsyncSocket",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                "Pow",
                .product(name: "Bugsnag", package: "bugsnag-cocoa"),
                "ColorfulX",
                "KSPlayer",
                "Kingfisher",
                "KingfisherWebP",
                "SimpleToast",
                .product(name: "Toasts", package: "swiftui-toasts"),
                .product(name: "InjectionNext", package: "InjectionNext")
            ],
            path: "Sources"
        ),
    ]
)
