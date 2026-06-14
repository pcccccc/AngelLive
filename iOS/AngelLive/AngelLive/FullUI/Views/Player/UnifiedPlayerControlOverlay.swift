//
//  UnifiedPlayerControlOverlay.swift
//  AngelLive
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import UIKit

struct UnifiedPlayerControlOverlay: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.safeAreaInsetsCustom) private var safeAreaInsets

    let bridge: PlayerControlBridge
    @Binding var showVideoSetting: Bool
    @Binding var showDanmakuSettings: Bool

    @State private var autoHideTask: Task<Void, Never>?
    @State private var isSettingsPopupOpen = false
    @State private var statusBarVM = StatusBarViewModel()
    @State private var videoScaleMode: VideoScaleMode = PlayerSettingModel().videoScaleMode
    @State private var showQualityPanel = false

    // 将 bridge.isMaskShow 的值提取到本地 @State 以便 SwiftUI 能可靠追踪变化
    @State private var isMaskVisible: Bool = true

    // MARK: - Computed Properties

    /// 是否处于全屏模式（iPad全屏 或 iPhone横屏）
    private var isFullscreen: Bool {
        if AppConstants.Device.isIPad {
            return isIPadFullscreen.wrappedValue
        }
        return isLandscape
    }

    /// 检测是否为横屏
    private var isLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    /// iPhone 横屏时需要忽略安全区
    private var shouldIgnoreSafeArea: Bool {
        isLandscape && !AppConstants.Device.isIPad
    }

    /// 控制层基础内边距。iPhone 横屏使用更统一的角落留白，避免和圆角节奏打架。
    private var controlPadding: CGFloat {
        if isLandscape {
            return AppConstants.Device.isIPad ? 20 : 16
        }
        return 12
    }

    /// 锁屏按钮单独按左侧安全区收进去，其余四角控制统一先试 25pt。
    private var iPhoneLandscapeLockInset: CGFloat {
        shouldIgnoreSafeArea ? safeAreaInsets.leading + 5 : 0
    }

    private var iPhoneLandscapeCornerInset: CGFloat {
        shouldIgnoreSafeArea ? 25 : 0
    }

    /// 顶部一排控制的目标高度，和返回按钮的 50pt 点击区对齐。
    private let topControlRowHeight: CGFloat = 50

    /// 顶部状态信息仅在全屏时显示，并放在屏幕宽度中心。
    private var showsCenteredStatusBar: Bool {
        isFullscreen
    }

    /// iPadOS 26 窗口控制按钮的参考几何：x=20, y=20, width=38, height=20。
    private var windowControlsFrame: CGRect? {
        guard AppConstants.Device.isIPad else { return nil }
        guard #available(iOS 26.0, *) else { return nil }
        return CGRect(x: 20, y: 20, width: 38, height: 20)
    }

    /// 仅在 iPad 窗口化运行时，为左上返回按钮预留红绿灯空间。
    private var shouldOffsetBackButtonForWindowControls: Bool {
        guard windowControlsFrame != nil else { return false }
        guard #available(iOS 26.0, *) else { return false }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return false
        }

        let sceneBounds = windowScene.effectiveGeometry.coordinateSpace.bounds
        let screenBounds = windowScene.screen.coordinateSpace.bounds
        let tolerance: CGFloat = 2

        return abs(sceneBounds.width - screenBounds.width) > tolerance ||
            abs(sceneBounds.height - screenBounds.height) > tolerance
    }

    private var windowControlsLeadingInset: CGFloat {
        guard shouldOffsetBackButtonForWindowControls, let frame = windowControlsFrame else { return 0 }
        return frame.maxX + 12
    }

    /// 顶部返回按钮与右上角控制层都使用 50pt 行高，统一下移 2pt 后继续保持 centerY 对齐。
    private var topControlPadding: CGFloat {
        guard windowControlsFrame != nil else { return controlPadding }
        return 7
    }

    private var centeredStatusBarTopPadding: CGFloat {
        5
    }

    /// 顶部阴影覆盖时间、电池和控制按钮，提升花屏背景下的可读性。
    private var topShadowHeight: CGFloat {
        (max(topControlPadding + topControlRowHeight, centeredStatusBarTopPadding + 20) + 32) * 0.75
    }

    private var topShadowGradient: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong),
                    .black.opacity(AppConstants.PlayerUI.Opacity.overlayLight),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topShadowHeight)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// 是否有弹窗/菜单展开
    private var isPopupOpen: Bool {
        showDanmakuSettings || showVideoSetting || isSettingsPopupOpen || showQualityPanel
    }

    var body: some View {
        ZStack {
            // 顶/底部渐变背景（锁定时隐藏）
            if !bridge.isLocked.wrappedValue {
                topShadowGradient
                    .opacity(isMaskVisible ? 1 : 0)

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            .clear,
                            .black.opacity(AppConstants.PlayerUI.Opacity.overlayLight),
                            .black.opacity(AppConstants.PlayerUI.Opacity.overlayStrong)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 80)
                }
                .ignoresSafeArea()
                .opacity(isMaskVisible ? 1 : 0)
                .allowsHitTesting(false)
            }

            // 控制按钮层
            ZStack {
                // 左侧中间：锁定按钮（始终显示）
                lockButton

                // 锁定时隐藏其余所有控制
                if !bridge.isLocked.wrappedValue {
                    if showsCenteredStatusBar {
                        topCenteredStatusBarLayer
                    }

                    // 左上角：返回按钮
                    backButtonLayer

                    // 右上角：功能按钮
                    topRightLayer

                    // 中间：暂停大按钮（加载/缓冲时不显示，避免「页面卡住」错觉，交给 loading overlay）
                    if !bridge.isPlaying && !bridge.isBuffering && !bridge.isInitialLoading {
                        Button {
                            bridge.togglePlayPause()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 62, height: 62)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // 左下角：播放/暂停、刷新
                    bottomLeftLayer

                    // 右下角：弹幕、清晰度、全屏
                    bottomRightLayer
                }
            }
            .padding(.leading, controlPadding)
            .padding(.trailing, controlPadding)
            .padding(.bottom, controlPadding)
            .opacity(isMaskVisible ? 1 : 0)
            .allowsHitTesting(isMaskVisible)
            .ignoresSafeArea(shouldIgnoreSafeArea ? .all : [])
            // 触摸控制层时重置自动隐藏
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        if isMaskVisible && !isPopupOpen {
                            startAutoHideTimer()
                        }
                    }
            )
            // 清晰度选择面板（右侧滑入）
            if showQualityPanel {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showQualityPanel = false }
                QualitySelectionPanel(isShowing: $showQualityPanel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showQualityPanel)
        // 双向同步 bridge.isMaskShow ↔ isMaskVisible
        .onChange(of: bridge.isMaskShow.wrappedValue) { _, newValue in
            if isMaskVisible != newValue {
                isMaskVisible = newValue
            }
        }
        .onChange(of: isMaskVisible) { _, newValue in
            if bridge.isMaskShow.wrappedValue != newValue {
                bridge.isMaskShow.wrappedValue = newValue
            }
            // 自动隐藏计时器管理
            if newValue && !isPopupOpen {
                startAutoHideTimer()
            } else if !newValue {
                cancelAutoHideTimer()
            }
        }
        .onChange(of: showDanmakuSettings) { _, isShowing in
            if !isShowing && isMaskVisible && !isPopupOpen {
                startAutoHideTimer()
            } else if isShowing {
                cancelAutoHideTimer()
            }
        }
        .onChange(of: showVideoSetting) { _, isShowing in
            if !isShowing && isMaskVisible && !isPopupOpen {
                startAutoHideTimer()
            } else if isShowing {
                cancelAutoHideTimer()
            }
        }
        .onChange(of: showQualityPanel) { _, isShowing in
            if !isShowing && isMaskVisible && !isPopupOpen {
                startAutoHideTimer()
            } else if isShowing {
                cancelAutoHideTimer()
            }
        }
        .onAppear {
            isMaskVisible = bridge.isMaskShow.wrappedValue
            if isMaskVisible && !isPopupOpen {
                startAutoHideTimer()
            }
        }
        .onDisappear {
            cancelAutoHideTimer()
        }
    }

    // MARK: - Lock Button

    private var lockButton: some View {
        VStack {
            Spacer()
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        bridge.isLocked.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: bridge.isLocked.wrappedValue ? "lock.fill" : "lock.open")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, iPhoneLandscapeLockInset)
                Spacer()
            }
            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Back Button

    private var backButtonLayer: some View {
        VStack {
            HStack {
                Button {
                    handleBackButton()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .padding(10)
                        .contentShape(Rectangle())
                }
                .padding(-10)
                .buttonStyle(.plain)
                .padding(.leading, windowControlsLeadingInset + iPhoneLandscapeCornerInset)
                Spacer()
            }
            Spacer()
        }
        .padding(.top, topControlPadding)
        .transition(.opacity)
    }

    // MARK: - Top Center / Top Right

    private var topCenteredStatusBarLayer: some View {
        VStack {
            statusBarContent
                .frame(maxWidth: .infinity)
                .padding(.top, centeredStatusBarTopPadding)
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var topRightLayer: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    if bridge.supportsPictureInPicture {
                        Button {
                            bridge.togglePictureInPicture()
                        } label: {
                            Image(systemName: "pip")
                                .frame(width: 30, height: 30)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }

                    // 画面缩放（仅横屏/全屏时显示）
                    if isLandscape || isIPadFullscreen.wrappedValue {
                        scaleModeMenu
                    }

                    SettingsButton(
                        showVideoSetting: $showVideoSetting,
                        showDanmakuSettings: $showDanmakuSettings,
                        onDismiss: { dismiss() },
                        onPopupStateChanged: { isOpen in
                            isSettingsPopupOpen = isOpen
                            if isOpen {
                                cancelAutoHideTimer()
                            } else if isMaskVisible {
                                startAutoHideTimer()
                            }
                        }
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .frame(height: topControlRowHeight)
                .padding(.trailing, iPhoneLandscapeCornerInset)
            }
            Spacer()
        }
        .padding(.top, topControlPadding)
        .transition(.opacity)
    }

    // MARK: - Bottom Left (Play/Pause + Refresh)

    private var bottomLeftLayer: some View {
        VStack {
            Spacer()
            HStack {
                HStack(spacing: 16) {
                    Button {
                        bridge.togglePlayPause()
                    } label: {
                        Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 30, height: 30)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        bridge.refreshPlayback()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 30, height: 30)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.leading, iPhoneLandscapeCornerInset)
                Spacer()
            }
        }
    }

    // MARK: - Bottom Right (Danmu + Quality + Fullscreen)

    private var bottomRightLayer: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        viewModel.danmuSettings.showDanmu.toggle()
                    } label: {
                        Image(systemName: viewModel.danmuSettings.showDanmu ? "captions.bubble.fill" : "captions.bubble")
                            .frame(width: 30, height: 30)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    qualityMenu

                    Button {
                        toggleOrientationOrFullscreen()
                    } label: {
                        Image(systemName: fullscreenIconName)
                            .frame(width: 30, height: 30)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.trailing, iPhoneLandscapeCornerInset)
            }
        }
    }

    // MARK: - Status Bar Content

    @ViewBuilder
    private var statusBarContent: some View {
        HStack(spacing: 4) {
            Text(statusBarVM.formattedTime)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Image(systemName: statusBarVM.batteryIconName)
                .font(.system(size: 11))
                .foregroundStyle(statusBarVM.batteryColor)
        }
    }

    // MARK: - Quality Menu

    private var qualityMenu: some View {
        Button {
            showQualityPanel = true
        } label: {
            Text(viewModel.currentPlayQualityString)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legacy Quality Menu (commented out for rollback)
    /*
    private var qualityMenuLegacy: some View {
        Menu {
            if let playArgs = viewModel.currentRoomPlayArgs {
                ForEach(displayedCDNIndices(from: playArgs), id: \.self) { cdnIndex in
                    let cdn = playArgs[cdnIndex]
                    Menu {
                        ForEach(displayedQualityIndices(from: cdn), id: \.self) { urlIndex in
                            let quality = cdn.qualitys[urlIndex]
                            Button {
                                viewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex)
                            } label: {
                                HStack {
                                    Text(RoomPlaybackResolver.qualityDisplayTitle(quality, in: playArgs))
                                    if viewModel.currentCdnIndex == cdnIndex && viewModel.currentQualityIndex == urlIndex {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(cdn.cdn.isEmpty ? "线路 \(cdnIndex + 1)" : cdn.cdn)
                    }
                }
            }
        } label: {
            Text(viewModel.currentPlayQualityString)
                .foregroundStyle(.white)
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .tint(.primary)
    }
    */

    private func displayedCDNIndices(from playArgs: [LiveQualityModel]) -> [Int] {
        let indices = Array(playArgs.indices)
        return isFullscreen ? Array(indices.reversed()) : indices
    }

    private func displayedQualityIndices(from cdn: LiveQualityModel) -> [Int] {
        let indices = Array(cdn.qualitys.indices)
        return isFullscreen ? Array(indices.reversed()) : indices
    }

    // MARK: - Scale Mode Menu

    private var scaleModeMenu: some View {
        Menu {
            ForEach(VideoScaleMode.allCases, id: \.rawValue) { mode in
                Button {
                    videoScaleMode = mode
                    PlayerSettingModel().videoScaleMode = mode
                    bridge.applyScaleMode?(mode)
                } label: {
                    Label {
                        Text(mode.title)
                    } icon: {
                        Image(systemName: videoScaleMode == mode ? "checkmark" : mode.iconName)
                    }
                }
            }
        } label: {
            Image(systemName: videoScaleMode.iconName)
                .frame(width: 30, height: 30)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
        .tint(.primary)
    }

    // MARK: - Helpers

    private var fullscreenIconName: String {
        if AppConstants.Device.isIPad {
            return isIPadFullscreen.wrappedValue ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        }
        return isCurrentLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
    }

    /// 处理返回按钮点击
    /// - iPad 全屏时：退出全屏
    /// - iPhone 横屏时：切换回竖屏（不 dismiss）
    /// - 其他情况：dismiss 返回上一页
    private func handleBackButton() {
        if AppConstants.Device.isIPad && isIPadFullscreen.wrappedValue {
            isIPadFullscreen.wrappedValue = false
            return
        } else if !AppConstants.Device.isIPad && isCurrentLandscape {
            // iPhone 横屏：先切回竖屏，旋转完成后恢复自由旋转
            KSOptions.supportedInterfaceOrientations = .portrait

            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }

            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: .portrait
            )

            // 先通知 ViewController 刷新支持的方向
            if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            // 延迟到下一个 run loop，确保 VC 已刷新支持的方向
            DispatchQueue.main.async {
                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    Logger.warning("退出全屏失败: \(error)", category: .ui)
                }
                // 旋转完成后恢复自由旋转，允许再次横屏自动全屏
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                    if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                        rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                }
            }
        } else {
            // 竖屏：返回上一页
            dismiss()
            KSOptions.supportedInterfaceOrientations = .portrait
        }
    }

    private func toggleOrientationOrFullscreen() {
        if AppConstants.Device.isIPad {
            isIPadFullscreen.wrappedValue.toggle()
            return
        }

        let targetOrientation: UIInterfaceOrientationMask = isCurrentLandscape ? .portrait : .landscapeRight
        KSOptions.supportedInterfaceOrientations = targetOrientation

        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        // 先通知 ViewController 刷新支持的方向
        if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        // 延迟到下一个 run loop，确保 VC 已刷新支持的方向
        DispatchQueue.main.async {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: targetOrientation
            )
            windowScene.requestGeometryUpdate(geometryPreferences) { error in
                Logger.warning("方向更新失败: \(error)", category: .ui)
            }
            // 旋转完成后恢复自由旋转
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KSOptions.supportedInterfaceOrientations = .allButUpsideDown
                if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                    rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }

    private var isCurrentLandscape: Bool {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return false
        }
        return windowScene.interfaceOrientation.isLandscape
    }

    // MARK: - Auto Hide Timer

    private func startAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled && !isPopupOpen {
                isMaskVisible = false
            }
        }
    }

    private func cancelAutoHideTimer() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
