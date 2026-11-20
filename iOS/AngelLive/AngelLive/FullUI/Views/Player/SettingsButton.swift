//
//  SettingsButton.swift
//  AngelLive
//
//  Created by pangchong on 10/30/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

@Observable
final class FullUIPlaybackMenuState {
    enum Action: Equatable {
        case danmaku, subtitles, timer, cancelTimer, airPlay, dlna, settings, statistics
    }

    var isPresented = false
    var selectedAction: Action?

    func select(_ action: Action) {
        selectedAction = action
        isPresented = false
    }
}

/// 播放器设置按钮（视频信息统计、弹幕设置、投屏、定时关闭、播放设置）
struct SettingsButton: View {
    @Binding var showVideoSetting: Bool
    @Binding var showDanmakuSettings: Bool
    var onDismiss: () -> Void
    var onPopupStateChanged: ((Bool) -> Void)? // 弹窗状态变化回调
    var fullscreenMenu: FullUIPlaybackMenuState?
    var playbackTimer: TimerManager?

    @State private var showActionSheet = false
    @State private var showAirPlayPicker = false
    @State private var showDLNAPicker = false
    @State private var showTimerPicker = false
    @State private var showPlayerSettings = false
    @State private var showSubtitleSettings = false
    @State private var subtitleActivationID = UUID()
    @State private var localTimer = TimerManager()
    @State private var playerSettingModel = PlayerSettingModel()
    @Environment(RoomInfoViewModel.self) private var viewModel

    private var usesFullscreenChrome: Bool { fullscreenMenu != nil }
    private var timerManager: TimerManager { playbackTimer ?? localTimer }

    /// 是否有任何弹窗展开
    private var isAnyPopupOpen: Bool {
        showActionSheet || showAirPlayPicker || showDLNAPicker || showTimerPicker || showPlayerSettings || showSubtitleSettings
    }

    private var trigger: some View {
        let size: CGFloat = usesFullscreenChrome ? FullUIPlayerChrome.controlSize : 30
        return ZStack {
            Button(action: {
                if let fullscreenMenu {
                    fullscreenMenu.isPresented = true
                } else {
                    showActionSheet = true
                }
            }) {
                Image(systemName: "gearshape")
                    .frame(width: size, height: size)
                    .font(FullUIPlayerChrome.symbolFont)
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放器设置")

            // 定时器激活时显示倒计时
            if timerManager.isTimerActive {
                Text(timerManager.formattedTime)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.red)
                    )
                    .offset(y: -18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var settingsTrigger: some View {
        if usesFullscreenChrome {
            trigger
        } else {
            trigger.confirmationDialog("播放器设置", isPresented: $showActionSheet, titleVisibility: .visible) {
                legacyActions
            }
        }
    }

    @ViewBuilder private var legacyActions: some View {
        if viewModel.supportsDanmu {
            Button("弹幕设置") { perform(.danmaku) }
        }

        LiveSubtitleQuickControls(playback: viewModel.subtitlePlayback) {
            perform(.subtitles)
        }

        Button("翻译与字幕设置…") { perform(.subtitles) }

        if viewModel.canUseAirPlay {
            Button("AirPlay 投屏") { perform(.airPlay) }
        }
        if viewModel.dlnaCastResource != nil {
            Button("DLNA 投屏") { perform(.dlna) }
        }

        if timerManager.isTimerActive {
            Button("取消定时关闭 (\(timerManager.formattedTime))") { perform(.cancelTimer) }
        } else {
            Button("定时关闭") { perform(.timer) }
        }

        Button("播放设置") { perform(.settings) }
        Button("视频信息统计") { perform(.statistics) }
        Button("取消", role: .cancel) { showActionSheet = false }
    }

    var body: some View {
        settingsTrigger
        .tint(.primary)
        .sheet(isPresented: $showAirPlayPicker) {
            AirPlayPickerSheet()
                .presentationDetents([.height(200)])
                .presentationDragIndicator(.visible)
                .tint(.primary)
        }
        .sheet(isPresented: $showDLNAPicker) {
            if let resource = viewModel.dlnaCastResource {
                DLNADevicePickerSheet(resource: resource)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .tint(.primary)
            }
        }
        .sheet(isPresented: $showTimerPicker) {
            TimerPickerView { minutes in
                timerManager.startTimer(minutes: minutes) {
                    onDismiss()
                }
            }
            .tint(.primary)
        }
        .sheet(isPresented: $showPlayerSettings) {
            PlayerSettingsSheet(
                playerSettingModel: playerSettingModel,
                onAutoPiPChanged: viewModel.updateAutoPictureInPicture
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSubtitleSettings) {
            NavigationStack {
                Form {
                    if usesFullscreenChrome {
                        Section {
                            LiveSubtitleQuickControls(playback: viewModel.subtitlePlayback) {
                                subtitleActivationID = viewModel.subtitlePlayback.activationID
                            }
                        }
                    }
                    if viewModel.subtitlePlayback.phase == .manualSelectionRequired {
                        Section {
                            LiveSubtitleLanguageOptions(
                                playback: viewModel.subtitlePlayback,
                                activationID: subtitleActivationID
                            ) {
                                showSubtitleSettings = false
                            }
                        } header: {
                            Text("选择主播语言")
                        } footer: {
                            Text("暂时无法从音频确定语言。请选择与主播语音一致的语言，字幕将继续识别。")
                        }
                    }

                    Section {
                        NavigationLink("翻译与字幕设置") {
                            TranslationSettingView()
                        }
                    }
                }
                .navigationTitle("字幕设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            showSubtitleSettings = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .tint(.primary)
        }
        .onChange(of: isAnyPopupOpen) { _, isOpen in
            onPopupStateChanged?(isOpen)
        }
        .onChange(of: fullscreenMenu?.selectedAction) { _, action in
            guard let action else { return }
            fullscreenMenu?.selectedAction = nil
            perform(action)
        }
        .onChange(of: viewModel.subtitlePlayback.activationID) { _, _ in
            showSubtitleSettings = false
        }
    }

    private func perform(_ action: FullUIPlaybackMenuState.Action) {
        switch action {
        case .danmaku: showDanmakuSettings = true
        case .subtitles:
            subtitleActivationID = viewModel.subtitlePlayback.activationID
            showSubtitleSettings = true
        case .timer: showTimerPicker = true
        case .cancelTimer: timerManager.cancelTimer()
        case .airPlay: showAirPlayPicker = true
        case .dlna: showDLNAPicker = true
        case .settings: showPlayerSettings = true
        case .statistics: showVideoSetting = true
        }
    }
}

struct FullUIPlaybackMenu: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @State private var showCastOptions = false
    let state: FullUIPlaybackMenuState
    let timer: TimerManager
    let showsRoomIdentity: Bool

    private var hasCastOptions: Bool {
        viewModel.canUseAirPlay || viewModel.dlnaCastResource != nil
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            sections
            ScrollView { sections }
        }
        .frame(width: 240)
        .foregroundStyle(.white)
        .fullUIPlayerGlass(in: RoundedRectangle(cornerRadius: 24), interactive: false)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("播放器设置")
        .accessibilityAction(.escape) { state.isPresented = false }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsRoomIdentity {
                FullUIPlayerRoomIdentity(room: viewModel.currentRoom)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                Divider()
            }
            if showCastOptions {
                menuSection("投屏") {
                    menuRow("返回", symbol: "chevron.backward", showsChevron: false) { showCastOptions = false }
                    if viewModel.canUseAirPlay {
                        menuRow("AirPlay 投屏", symbol: "airplay.video") { state.select(.airPlay) }
                    }
                    if viewModel.dlnaCastResource != nil {
                        menuRow("DLNA 投屏", symbol: "tv") { state.select(.dlna) }
                    }
                }
            } else {
                menuSection("常用") {
                    if viewModel.supportsDanmu {
                        menuRow("弹幕", symbol: "captions.bubble") { state.select(.danmaku) }
                    }
                    menuRow("字幕与翻译", symbol: "captions.bubble.fill") { state.select(.subtitles) }
                    if timer.isTimerActive {
                        menuRow("取消定时关闭 (\(timer.formattedTime))", symbol: "timer", showsChevron: false) {
                            state.select(.cancelTimer)
                        }
                    } else {
                        menuRow("定时关闭", symbol: "timer") { state.select(.timer) }
                    }
                }
                if hasCastOptions {
                    Divider()
                    menuSection("投屏") {
                        menuRow("投屏", symbol: "airplay.video") { showCastOptions = true }
                    }
                }
                Divider()
                menuSection("更多") {
                    menuRow("播放设置", symbol: "gearshape") { state.select(.settings) }
                    menuRow("视频信息", symbol: "info.circle") { state.select(.statistics) }
                }
            }
        }
        .padding(8)
    }

    private func menuSection<Content: View>(_ title: String, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
    }

    private func menuRow(
        _ title: String,
        symbol: String,
        showsChevron: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(FullUIPlayerChrome.symbolFont)
                    .frame(width: 20)
                Text(title)
                    .font(.callout)
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Player Settings Sheet

/// 播放设置弹窗
private struct PlayerSettingsSheet: View {
    // @Observable 引用类型用 @Bindable 取属性绑定;早前误用 @Binding(绑定到类引用)
    // 不会对内部属性建立观察,导致首次点开关 onChange 不触发——「要操作两次才生效」的根因。
    @Bindable var playerSettingModel: PlayerSettingModel
    var onAutoPiPChanged: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// 当前内核是否支持画中画（VLC4 路径目前为 no-op）
    private var pipSupported: Bool {
        playerSettingModel.playerKernel == .ksplayer
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppConstants.Spacing.lg) {
                    // 播放设置
                    settingSection(title: "播放设置") {
                        VStack(spacing: 0) {
                            settingRow {
                                HStack {
                                    Text("播放器内核")
                                    Spacer()
                                    if PlayerKernelSupport.availableKernels.isEmpty {
                                        Text("不可用")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Picker("播放器内核", selection: $playerSettingModel.playerKernel) {
                                            ForEach(PlayerKernelSupport.availableKernels, id: \.self) { kernel in
                                                Text(kernel.title).tag(kernel)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                        .onChange(of: playerSettingModel.playerKernel) { _, newKernel in
                                            // 切到不支持 PiP 的内核时关掉自动 PiP，避免悬空状态
                                            if newKernel != .ksplayer && playerSettingModel.enableAutoPiPOnBackground {
                                                playerSettingModel.enableAutoPiPOnBackground = false
                                                onAutoPiPChanged()
                                            }
                                        }
                                    }
                                }
                            }

                            Divider()
                                .padding(.leading)

                            settingRow {
                                Toggle("后台播放", isOn: $playerSettingModel.enableBackgroundAudio)
                                    .tint(AppConstants.Colors.accent)
                                    .onChange(of: playerSettingModel.enableBackgroundAudio) { _, newValue in
                                        KSOptions.canBackgroundPlay = newValue
                                        // 关后台播放时，自动 PiP 必然失效，一起关掉
                                        if !newValue && playerSettingModel.enableAutoPiPOnBackground {
                                            playerSettingModel.enableAutoPiPOnBackground = false
                                            onAutoPiPChanged()
                                        }
                                    }
                            }

                            Divider()
                                .padding(.leading)

                            settingRow {
                                VStack(alignment: .leading, spacing: 4) {
                                    Toggle("自动画中画", isOn: $playerSettingModel.enableAutoPiPOnBackground)
                                        .tint(AppConstants.Colors.accent)
                                        .disabled(!pipSupported)
                                        .onChange(of: playerSettingModel.enableAutoPiPOnBackground) { _, newValue in
                                            if newValue && !playerSettingModel.enableBackgroundAudio {
                                                playerSettingModel.enableBackgroundAudio = true
                                                KSOptions.canBackgroundPlay = true
                                            }
                                            onAutoPiPChanged()
                                        }

                                    Text(pipSupported
                                         ? "开启后会自动启用后台播放"
                                         : "当前内核（VLC4）暂不支持画中画")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer(minLength: AppConstants.Spacing.xl)
                }
                .padding()
            }
            .background(.ultraThinMaterial)
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        KSOptions.canBackgroundPlay = playerSettingModel.enableBackgroundAudio
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                }
            }
        }
        .onAppear {
            KSOptions.canBackgroundPlay = playerSettingModel.enableBackgroundAudio
            let resolvedKernel = PlayerKernelSupport.resolvedKernel(for: playerSettingModel.playerKernel)
            if resolvedKernel != playerSettingModel.playerKernel {
                playerSettingModel.playerKernel = resolvedKernel
            }
        }
    }

    // MARK: - Helper Views

    /// 设置分组
    @ViewBuilder
    private func settingSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .padding(.horizontal)

            content()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)
        }
    }

    /// 设置行
    @ViewBuilder
    private func settingRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding()
    }
}

// MARK: - AirPlay Picker Sheet

/// AirPlay 投屏选择器弹窗
private struct AirPlayPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("选择投屏设备")
                    .font(.headline)
                    .padding(.top)

                AirPlayView()
                    .frame(width: 60, height: 60)

                Text("点击上方按钮选择 AirPlay 设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .navigationTitle("投屏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SettingsButton(
            showVideoSetting: .constant(false),
            showDanmakuSettings: .constant(false),
            onDismiss: {}
        )
    }
}
