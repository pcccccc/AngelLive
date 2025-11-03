//
//  PlayerContainerView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import UIKit

// MARK: - Preference Key for Player Height

struct PlayerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preference Key for Vertical Live Mode

struct VerticalLiveModePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

// MARK: - Vertical Live Mode Environment Key

struct VerticalLiveModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Safe Area Insets Environment Key

struct SafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue: EdgeInsets = EdgeInsets()
}

extension EnvironmentValues {
    var safeAreaInsetsCustom: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}

/// 播放器容器视图
struct PlayerContainerView: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @ObservedObject var coordinator: KSVideoPlayer.Coordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // 检测是否为 iPad 横屏
    private var isIPadLandscape: Bool {
        AppConstants.Device.isIPad &&
        horizontalSizeClass == .regular &&
        verticalSizeClass == .compact
    }

    var body: some View {
        PlayerContentView(playerCoordinator: coordinator)
            .environment(viewModel)
    }
}

struct PlayerContentView: View {

    @Environment(RoomInfoViewModel.self) private var viewModel
    @ObservedObject var playerCoordinator: KSVideoPlayer.Coordinator
    @State private var videoAspectRatio: CGFloat = 16.0 / 9.0 // 默认 16:9 横屏，减少跳动
    @State private var isVideoPortrait: Bool = false
    @State private var hasDetectedSize: Bool = false // 是否已检测到真实尺寸
    @State private var isVerticalLiveMode: Bool = false // 是否为竖屏直播模式
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // 检测设备是否为横屏
    private var isDeviceLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    // 生成基于方向的唯一 key
    private var playerViewKey: String {
        "\(viewModel.currentPlayURL?.absoluteString ?? "")_\(isDeviceLandscape ? "landscape" : "portrait")"
    }

    var body: some View {
        GeometryReader { geometry in
            let playerHeight = calculatedHeight(for: geometry.size)

            playerContent
            .frame(
                width: geometry.size.width,
                height: isVerticalLiveMode ? nil : playerHeight
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: isVerticalLiveMode ? .infinity : nil,
                alignment: .center
            )
            .background(AppConstants.Device.isIPad ? Color.black : (isDeviceLandscape ? Color.black : Color.clear))
            .preference(key: PlayerHeightPreferenceKey.self, value: playerHeight)
            .preference(key: VerticalLiveModePreferenceKey.self, value: isVerticalLiveMode)
        }
        .edgesIgnoringSafeArea(isVerticalLiveMode ? .all : [])
    }

    // 计算视频高度
    private func calculatedHeight(for size: CGSize) -> CGFloat {
        let shouldFillHeight = isDeviceLandscape || AppConstants.Device.isIPad || isVerticalLiveMode
        let calculatedByRatio = size.width / videoAspectRatio

        return shouldFillHeight ? size.height : calculatedByRatio
    }

    // MARK: - Player Content

    private var playerContent: some View {
        Group {
            // 如果有播放地址，显示播放器
            if let playURL = viewModel.currentPlayURL {
                KSVideoPlayerView(
                    coordinator: playerCoordinator,
                    url: playURL,
                    options: viewModel.playerOption
                ) { coordinator, isDisappear in
                    if !isDisappear {
                        viewModel.setPlayerDelegate(playerCoordinator: coordinator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: isVerticalLiveMode ? .infinity : nil)
                .clipped()
                .opacity(hasDetectedSize ? 1 : 0)
                .task(id: playURL.absoluteString) {
                    // 使用异步任务定期检查视频尺寸
                    var retryCount = 0
                    let maxRetries = 40 // 最多重试 40 次（10 秒）

                    print("🔍 开始检测视频尺寸... URL: \(playURL.absoluteString)")

                    while !Task.isCancelled && retryCount < maxRetries {
                        if let naturalSize = playerCoordinator.playerLayer?.player.naturalSize,
                           naturalSize.width > 0, naturalSize.height > 0 {

                            // 检查是否为有效尺寸（排除 1.0 x 1.0 等占位符）
                            let isValidSize = naturalSize.width > 1.0 && naturalSize.height > 1.0

                            if !isValidSize {
                                print("⚠️ 检测到无效视频尺寸: \(naturalSize.width) x \(naturalSize.height)，继续等待... (\(retryCount)/\(maxRetries))")
                            } else if !hasDetectedSize {
                                let ratio = naturalSize.width / naturalSize.height
                                let isPortrait = ratio < 1.0
                                let isVerticalLive = isPortrait && naturalSize.height >= 1280

                                print("📺 视频尺寸: \(naturalSize.width) x \(naturalSize.height)")
                                print("📐 视频比例: \(ratio)")
                                print("📱 视频方向: \(isPortrait ? "竖屏" : "横屏")")
                                print("🖥️ 设备方向: \(isDeviceLandscape ? "横屏" : "竖屏")")

                                if isVerticalLive {
                                    print("🎬 检测到竖屏直播模式！高度: \(naturalSize.height)")
                                }

                                await MainActor.run {
                                    applyVideoFillMode(isVerticalLive: isVerticalLive)

                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        videoAspectRatio = ratio
                                        isVideoPortrait = isPortrait
                                        isVerticalLiveMode = isVerticalLive
                                        hasDetectedSize = true
                                    }
                                }

                                // 打印应用的策略
                                if isDeviceLandscape && isPortrait {
                                    print("✅ 应用策略: 横屏设备+竖屏视频 → 限制宽度，居中显示")
                                } else {
                                    print("✅ 应用策略: 标准 aspect fit 显示")
                                }

                                break // 获取到后退出循环
                            } else {
                                // 已经检测过，直接退出
                                print("✅ 已有视频尺寸信息，无需重复检测")
                                break
                            }
                        }

                        retryCount += 1
                        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25秒
                    }

                    // 超时后仍未获取到有效尺寸，强制显示（使用默认 16:9 比例）
                    if retryCount >= maxRetries && !hasDetectedSize {
                        print("⚠️ 无法获取有效视频尺寸，强制显示（默认 16:9 比例）")
                        await MainActor.run {
                            applyVideoFillMode(isVerticalLive: false)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hasDetectedSize = true
                            }
                        }
                    }
                }
                .onChange(of: playURL) { _ in
                    // 切换视频时重置为默认 16:9 比例并重新检测
                    print("🔄 切换视频，重置为默认 16:9 比例")
                    videoAspectRatio = 16.0 / 9.0
                    isVideoPortrait = false
                    isVerticalLiveMode = false
                    hasDetectedSize = false
                    applyVideoFillMode(isVerticalLive: false) // 重置为默认的 fit 模式
                    // task(id: playURL.absoluteString) 会自动触发重新检测
                }
            } else {
                if viewModel.isLoading {
                    // 加载中
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("正在解析直播地址...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    // 封面图作为背景
                    KFImage(URL(string: viewModel.currentRoom.roomCover))
                        .placeholder {
                            Rectangle()
                                .fill(AppConstants.Colors.placeholderGradient())
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        }
    }

    // 判断是否需要限制宽度（横屏设备 + 竖屏视频）
    private var shouldLimitWidth: Bool {
        isDeviceLandscape && isVideoPortrait
    }

    @MainActor
    private func applyVideoFillMode(isVerticalLive: Bool) {
        playerCoordinator.isScaleAspectFill = isVerticalLive

        guard let playerLayer = playerCoordinator.playerLayer else {
            return
        }

        let targetContentMode: UIView.ContentMode = isVerticalLive ? .scaleAspectFill : .scaleAspectFit

        if playerLayer.player.contentMode != targetContentMode {
            playerLayer.player.contentMode = targetContentMode
        }

        let playerView = playerLayer.player.view
        playerView.clipsToBounds = isVerticalLive
        playerView.layer.masksToBounds = isVerticalLive
        playerView.setNeedsLayout()
        playerView.layoutIfNeeded()
    }
}

// MARK: - Video Aspect Ratio Modifier

/// 视频比例修饰器
/// - 所有情况: 填满容器，无比例限制
private struct VideoAspectRatioModifier: ViewModifier {
    let aspectRatio: CGFloat?
    let isIPad: Bool
    let isLandscape: Bool

    func body(content: Content) -> some View {
        // 所有情况都填满容器，不设置 aspectRatio
        content
    }
}
