//
//  TVQualitySelectionPanel.swift
//  AngelLiveTVOS
//

import SwiftUI
import AngelLiveCore

/// tvOS 播放器内嵌清晰度/线路选择面板，右侧滑入覆盖，不离开播放画面即可切换
struct TVQualitySelectionPanel: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.usesFullUI) private var usesFullUI

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var reducesPanelMotion: Bool { usesFullUI && reduceMotion }

    let accountRecoveryIsActive: Bool
    @Binding var loginReturnQuality: QualityIdentity?
    let onSelect: (_ cdnIndex: Int, _ urlIndex: Int) -> RoomInfoViewModel.PlaybackQualitySelectionResult
    let onClose: () -> Void

    @FocusState private var focusedItem: FocusItem?
    @State private var expandedSections: Set<Int> = []
    @State private var hasInitializedFocus = false
    struct QualityIdentity: Equatable {
        let cdn: String
        let lineName: String?
        let qualityNumber: Int
        let qualityTitle: String
    }

    private enum FocusItem: Hashable {
        case close
        case cdnHeader(Int)
        case quality(cdnIndex: Int, urlIndex: Int)
    }

    /// 只有一个 CDN 时不需要折叠
    private var canCollapse: Bool {
        (viewModel.currentRoomPlayArgs?.count ?? 0) > 1
    }

    var body: some View {
        Group {
            if usesFullUI {
                panelContent.tvPlayerPanelSurface()
            } else {
                panelContent
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .adaptiveGlassEffectRoundedRect(cornerRadius: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            }
        }
        .disabled(accountRecoveryIsActive)
        .onAppear {
            guard !usesFullUI || !hasInitializedFocus else { return }
            hasInitializedFocus = true
            let cdnIdx = viewModel.currentCdnIndex

            // 默认展开当前选中的线路；只有一个 CDN 时全部展开
            if canCollapse {
                expandedSections = [cdnIdx]
            } else if let count = viewModel.currentRoomPlayArgs?.count {
                expandedSections = Set(0..<count)
            }

            if !usesFullUI || (!accountRecoveryIsActive && loginReturnQuality == nil) {
                focusedItem = currentQualityFocus
            }
        }
        .task(id: accountRecoveryIsActive) {
            guard usesFullUI else { return }
            if accountRecoveryIsActive {
                focusedItem = nil
                return
            }
            guard let target = loginReturnQuality else { return }
            await Task.yield()
            guard !Task.isCancelled, loginReturnQuality == target else { return }
            let focus = matchingQualityFocus(target) ?? currentQualityFocus
            if case .quality(let cdnIndex, _) = focus, expandedSections.insert(cdnIndex).inserted {
                await Task.yield()
                guard !Task.isCancelled, loginReturnQuality == target else { return }
            }
            focusedItem = focus
            loginReturnQuality = nil
        }
    }

    private var currentQualityFocus: FocusItem {
        let cdnIndex = viewModel.currentCdnIndex
        let urlIndex = viewModel.currentQualityIndex
        guard RoomPlaybackResolver.selection(in: viewModel.currentRoomPlayArgs, cdnIndex: cdnIndex, qualityIndex: urlIndex) != nil else {
            return .close
        }
        return .quality(cdnIndex: cdnIndex, urlIndex: urlIndex)
    }

    private func matchingQualityFocus(_ target: QualityIdentity) -> FocusItem? {
        guard let playArgs = viewModel.currentRoomPlayArgs else { return nil }
        for (cdnIndex, cdn) in playArgs.enumerated() where cdn.cdn == target.cdn && cdn.displayName == target.lineName {
            if let urlIndex = cdn.qualitys.firstIndex(where: { $0.qn == target.qualityNumber && $0.title == target.qualityTitle }) {
                return .quality(cdnIndex: cdnIndex, urlIndex: urlIndex)
            }
        }
        return nil
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            if usesFullUI {
                TVPlayerPanelHeader(title: Text("清晰度"), subtitle: normalizedQualityTitle.map { Text("当前：\($0)") }) {
                    TVPlayerPanelCloseButton(isFocused: focusedItem == .close, action: onClose)
                        .focused($focusedItem, equals: .close)
                }
            } else {
                header
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if let playArgs = viewModel.currentRoomPlayArgs {
                        ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                            cdnSection(cdnIndex: cdnIndex, cdn: cdn, playArgs: playArgs)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, usesFullUI ? 12 : 0)
                .padding(.vertical, usesFullUI ? 6 : 0)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("清晰度")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)

                if let currentTitle = normalizedQualityTitle {
                    Text("当前：\(currentTitle)")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 8)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(TVPanelCloseButtonStyle(isFocused: focusedItem == .close))
            .focused($focusedItem, equals: .close)
        }
    }

    // MARK: - CDN Section

    @ViewBuilder
    private func cdnSection(cdnIndex: Int, cdn: LiveQualityModel, playArgs: [LiveQualityModel]) -> some View {
        let isExpanded = expandedSections.contains(cdnIndex)
        let isCurrentCdn = viewModel.currentCdnIndex == cdnIndex
        let headerFocused = focusedItem == .cdnHeader(cdnIndex)

        VStack(alignment: .leading, spacing: 0) {
            // Section 标题（可折叠时变为按钮）
            if canCollapse {
                Button {
                    withAnimation(reducesPanelMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) {
                        if isExpanded {
                            expandedSections.remove(cdnIndex)
                        } else {
                            expandedSections.insert(cdnIndex)
                        }
                    }
                } label: {
                    cdnHeaderContent(cdnIndex: cdnIndex, cdn: cdn, isExpanded: isExpanded, isCurrentCdn: isCurrentCdn)
                }
                .buttonStyle(TVCdnHeaderButtonStyle(isFocused: headerFocused, reduceMotion: reducesPanelMotion))
                .focused($focusedItem, equals: .cdnHeader(cdnIndex))
            } else {
                cdnHeaderContent(cdnIndex: cdnIndex, cdn: cdn, isExpanded: true, isCurrentCdn: isCurrentCdn)
                    .padding(.bottom, 12)
            }

            // 清晰度列表
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(cdn.qualitys.enumerated()), id: \.offset) { urlIndex, quality in
                        let selected = viewModel.currentCdnIndex == cdnIndex && viewModel.currentQualityIndex == urlIndex
                        let isFocused = focusedItem == .quality(cdnIndex: cdnIndex, urlIndex: urlIndex)
                        Button {
                            let result = onSelect(cdnIndex, urlIndex)
                            if usesFullUI && result == .loginRecovery {
                                loginReturnQuality = QualityIdentity(
                                    cdn: cdn.cdn,
                                    lineName: cdn.displayName,
                                    qualityNumber: quality.qn,
                                    qualityTitle: quality.title
                                )
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Text(usesFullUI
                                     ? PlaybackDisplay.qualityTitle(quality, in: playArgs)
                                     : RoomPlaybackResolver.qualityDisplayTitle(quality, in: playArgs))
                                    .font(.system(size: 28, weight: (selected || isFocused) ? .semibold : .regular))
                                    .foregroundStyle(selected ? .white : .white.opacity(isFocused ? 0.95 : 0.8))

                                // 插件标记当前账号拿不到的档位（登录 / 会员）
                                if let lockTitle = RoomPlaybackResolver.lockBadgeTitle(for: quality) {
                                    if usesFullUI {
                                        TVPlayerLockBadge(title: lockTitle)
                                    } else {
                                        RequiresLoginTag(lockTitle, size: .regular).lineLimit(1)
                                    }
                                }

                                Spacer()

                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(usesFullUI && isFocused ? .white : Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                            .background {
                                if usesFullUI && isFocused {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(.black.opacity(0.8))
                                        .overlay { RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.25)) }
                                } else {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selected ? Color.accentColor.opacity(0.2) : isFocused ? .white.opacity(0.25) : .clear)
                                }
                            }
                        }
                        .buttonStyle(TVQualityItemButtonStyle(isFocused: isFocused, reduceMotion: reducesPanelMotion))
                        .focused($focusedItem, equals: .quality(cdnIndex: cdnIndex, urlIndex: urlIndex))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                    )
                )
            }
        }
    }

    // MARK: - CDN Header Content

    private func cdnHeaderContent(cdnIndex: Int, cdn: LiveQualityModel, isExpanded: Bool, isCurrentCdn: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
            Text(usesFullUI ? PlaybackDisplay.lineTitle(for: cdn, index: cdnIndex)
                            : cdn.cdn.isEmpty ? "线路 \(cdnIndex + 1)" : cdn.cdn)
                .font(.system(size: 22, weight: .semibold))

            if isCurrentCdn {
                Text("当前")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(usesFullUI ? Color.white : Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }

            Spacer()

            if canCollapse {
                Text("\(cdn.qualitys.count) 个清晰度")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(usesFullUI ? 0.85 : 0.4))

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(usesFullUI ? 0.85 : 0.4))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .foregroundStyle(.white.opacity(usesFullUI ? 0.9 : 0.5))
        .padding(.horizontal, canCollapse ? 16 : 0)
        .padding(.vertical, canCollapse ? 14 : 0)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private var normalizedQualityTitle: String? {
        let trimmed = (usesFullUI ? viewModel.fullUIQualityTitle : viewModel.currentPlayQualityString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "清晰度" else { return nil }
        return trimmed
    }
}


// MARK: - tvOS Button Styles

/// 清晰度选项按钮样式：聚焦时微缩放 + 高亮
struct TVQualityItemButtonStyle: ButtonStyle {
    let isFocused: Bool
    let reduceMotion: Bool

    init(isFocused: Bool, reduceMotion: Bool = false) {
        self.isFocused = isFocused
        self.reduceMotion = reduceMotion
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && isFocused ? 1.03 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isFocused)
    }
}

/// 关闭按钮样式：圆形 glass 背景 + 聚焦缩放
struct TVPanelCloseButtonStyle: ButtonStyle {
    @Environment(\.usesFullUI) private var usesFullUI
    let isFocused: Bool
    let reduceMotion: Bool

    init(isFocused: Bool, reduceMotion: Bool = false) {
        self.isFocused = isFocused
        self.reduceMotion = reduceMotion
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(isFocused ? 0.3 : 0.1))
                    .background(.black.opacity(usesFullUI && isFocused ? 0.8 : 0), in: Circle())
            }
            .scaleEffect(!reduceMotion && isFocused ? 1.1 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isFocused)
    }
}

/// CDN 线路标题按钮样式：聚焦时高亮背景
private struct TVCdnHeaderButtonStyle: ButtonStyle {
    @Environment(\.usesFullUI) private var usesFullUI
    let isFocused: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? .white.opacity(0.15) : .clear)
            )
            .background(.black.opacity(usesFullUI && isFocused ? 0.8 : 0), in: .rect(cornerRadius: 14))
            .scaleEffect(!reduceMotion && isFocused ? 1.02 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isFocused)
    }
}

/// Explicit FullUI control geometry. A square capsule is the same circle used by
/// the panel close button; text capsules keep the identical height and shell inset.
enum TVFullUIPlayerControlMetrics {
    static let height: CGFloat = 70
    static let spacing: CGFloat = 16
    static let inset: CGFloat = 14
    static let screenInset: CGFloat = 70
    static let focusOutset: CGFloat = 2
    static let groupHeight = height + 2 * inset
    static let bottomControlBand = screenInset + groupHeight

    static func visibilityAnimation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.2)
    }
}

enum TVPlayerControlShape { case circle, capsule }

/// Invisible focus targets must not acquire tvOS's system button material or scale.
/// Used only by FullUI; Select and remote commands remain owned by the host views.
struct TVFullUIHiddenControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct TVFullUIPlayerControlButtonModifier: ViewModifier {
    let enabled: Bool
    let isFocused: Bool
    let shape: TVPlayerControlShape
    var legacyShape: TVPlayerControlShape? = nil
    var legacyHeight: CGFloat? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.buttonStyle(TVFullUIPlayerControlButtonStyle(isFocused: isFocused, shape: shape))
        } else {
            switch legacyShape {
            case .circle:
                content.frame(height: legacyHeight).clipShape(.circle)
            case .capsule:
                content.frame(height: legacyHeight).clipShape(.capsule)
            case nil:
                content
            }
        }
    }
}

struct TVFullUIPlayerControlGroupModifier: ViewModifier {
    let enabled: Bool
    let legacyInsets: EdgeInsets

    @ViewBuilder
    func body(content: Content) -> some View {
        let inset = TVFullUIPlayerControlMetrics.inset
        let group = content.padding(enabled ? EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset) : legacyInsets)
        if enabled {
            group.tvPlayerGlass(in: Capsule())
        } else {
            group.adaptiveGlassEffectCapsule()
        }
    }
}

private struct TVFullUIPlayerControlButtonStyle: ButtonStyle {
    let isFocused: Bool
    let shape: TVPlayerControlShape
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let focusOutset = isFocused ? TVFullUIPlayerControlMetrics.focusOutset : 0
        return configuration.label
            .padding(.horizontal, shape == .capsule ? 24 : 0)
            .frame(width: shape == .circle ? TVFullUIPlayerControlMetrics.height : nil,
                   height: TVFullUIPlayerControlMetrics.height)
            .background {
                Capsule()
                    .fill(.white.opacity(isFocused ? 0.3 : 0.1))
                    .padding(-focusOutset)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isFocused)
    }
}

struct TVFullUIPlayerControlGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: TVFullUIPlayerControlMetrics.spacing, content: content)
            .modifier(TVFullUIPlayerControlGroupModifier(enabled: true, legacyInsets: EdgeInsets()))
            .focusSection()
    }
}
