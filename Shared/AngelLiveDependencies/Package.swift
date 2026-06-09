// swift-tools-version: 6.2

import Foundation
import PackageDescription

/// 通过环境变量 `USE_VLC=1` 切换播放器内核。
/// 默认使用 KSPlayer；设置 USE_VLC=1 后改用 VLCKit。
/// 两者不能同时引入，否则内嵌的 FFmpeg 符号会冲突。
private let useVLC = ProcessInfo.processInfo.environment["USE_VLC"] == "1"

private func resolveFFmpegKitDependency() -> Package.Dependency? {
    guard !useVLC else { return nil }
    // Force KSPlayer/KSMEPlayer onto the LGPL FFmpegKit line.
    // 8.1.1 标签当前指向 lgpl 分支 HEAD,固定 exact 避免分支漂移。
    return .package(url: "https://github.com/TracyPlayer/FFmpegKit", exact: "8.1.1")
}

private func resolveKSPlayerDependency() -> (package: Package.Dependency, target: Target.Dependency)? {
    guard !useVLC else { return nil }
    return (
        .package(url: "https://github.com/TracyPlayer/KSPlayer", exact: "3.1.0"),
        "KSPlayer"
    )
}

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/vtourraine/AcknowList", from: "3.4.0"),
    .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2"),
    .package(url: "https://github.com/bugsnag/bugsnag-cocoa", from: "6.34.0"),
    .package(url: "https://github.com/hyperoslo/Cache", from: "7.4.0"),
    .package(url: "https://github.com/Lakr233/ColorfulX", from: "5.2.8"),
    .package(url: "https://github.com/robbiehanson/CocoaAsyncSocket", from: "7.6.5"),
    .package(url: "https://github.com/1024jp/GzipSwift", from: "6.1.0"),
    .package(url: "https://github.com/onevcat/Kingfisher", from: "8.6.0"),
    .package(url: "https://github.com/yeatse/KingfisherWebP.git", from: "1.7.0"),
]

if let ffmpegKitDependency = resolveFFmpegKitDependency() {
    packageDependencies.append(ffmpegKitDependency)
}

// VLCKitSPM 仅在 USE_VLC=1 时引入（与 KSPlayer 互斥，避免 FFmpeg 符号冲突）
if useVLC {
    packageDependencies.append(
        .package(url: "https://github.com/rursache/VLCKitSPM", revision: "94ca521c32a9c1cd76824a34ab82e9ddb3360e65")
    )
}

packageDependencies += [
    .package(url: "https://github.com/EmergeTools/Pow", branch: "main"),
    .package(url: "https://github.com/sanzaru/SimpleToast", from: "0.11.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.86.2"),
    .package(url: "https://github.com/markiv/SwiftUI-Shimmer", branch: "iOS17-animate-start-end-points"),
    .package(url: "https://github.com/gunterhager/UDPBroadcastConnection", from: "5.0.5"),
    .package(url: "https://github.com/sunghyun-k/swiftui-toasts", from: "1.1.1"),
    .package(url: "https://github.com/sunghyun-k/swiftui-window-overlay.git", from: "1.0.2"),
    .package(url: "https://github.com/siteline/SwiftUI-Introspect", from: "1.3.0"),
]

var targetDependencies: [Target.Dependency] = [
    "Alamofire",
    .product(name: "Cache", package: "Cache"),
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
    "Kingfisher",
    "KingfisherWebP",
    // 只在 iOS 平台包含 WindowOverlay 和 Toasts
    .product(name: "WindowOverlay", package: "swiftui-window-overlay", condition: .when(platforms: [.iOS])),
    .product(name: "Toasts", package: "swiftui-toasts", condition: .when(platforms: [.iOS])),
    // 只在 tvOS 平台包含 SimpleToast
    .product(name: "SimpleToast", package: "SimpleToast", condition: .when(platforms: [.tvOS])),
    .product(name: "SwiftUIIntrospect", package: "SwiftUI-Introspect", condition: .when(platforms: [.iOS]))
]

if let ksPlayerDependency = resolveKSPlayerDependency() {
    packageDependencies.append(ksPlayerDependency.package)
    targetDependencies.append(ksPlayerDependency.target)
}

if useVLC {
    targetDependencies.append(.product(name: "VLCKitSPM", package: "VLCKitSPM"))
}

let package = Package(
    name: "AngelLiveDependencies",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "AngelLiveDependencies",
            targets: ["AngelLiveDependencies"]
        ),
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "AngelLiveDependencies",
            dependencies: targetDependencies,
            path: "Sources",
            // Resources/ 下放 Bugsnag 配置 plist:
            // - BugsnagSecrets.plist        占位(git 跟踪,空值)
            // - BugsnagSecrets.local.plist  真 key(gitignored,可选)
            // .process 对目录里所有文件按 build rule 处理;文件不存在不会报错,
            // 因此 local.plist 缺失也能编译。
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
