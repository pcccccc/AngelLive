//
//  TVQualitySelectionPanel.swift
//  AngelLiveTVOS
//

import SwiftUI
import AngelLiveCore

/// tvOS 播放器内嵌清晰度/线路选择面板，右侧滑入覆盖，不离开播放画面即可切换
struct TVQualitySelectionPanel: View {
    @Environment(RoomInfoViewModel.self) private var viewModel

    let onSelect: (_ cdnIndex: Int, _ urlIndex: Int) -> Void
    let onClose: () -> Void

    @FocusState private var focusedItem: FocusItem?
    @State private var expandedSections: Set<Int> = []

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
        VStack(alignment: .leading, spacing: 28) {
            header

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if let playArgs = viewModel.currentRoomPlayArgs {
                        ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                            cdnSection(cdnIndex: cdnIndex, cdn: cdn, playArgs: playArgs)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .onAppear {
            let cdnIdx = viewModel.currentCdnIndex
            let qualIdx = viewModel.currentQualityIndex

            // 默认展开当前选中的线路；只有一个 CDN 时全部展开
            if canCollapse {
                expandedSections = [cdnIdx]
            } else if let count = viewModel.currentRoomPlayArgs?.count {
                expandedSections = Set(0..<count)
            }

            // 聚焦到当前选中项
            if let playArgs = viewModel.currentRoomPlayArgs,
               cdnIdx < playArgs.count,
               qualIdx < playArgs[cdnIdx].qualitys.count {
                focusedItem = .quality(cdnIndex: cdnIdx, urlIndex: qualIdx)
            } else {
                focusedItem = .close
            }
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        if isExpanded {
                            expandedSections.remove(cdnIndex)
                        } else {
                            expandedSections.insert(cdnIndex)
                        }
                    }
                } label: {
                    cdnHeaderContent(cdnIndex: cdnIndex, cdn: cdn, isExpanded: isExpanded, isCurrentCdn: isCurrentCdn)
                }
                .buttonStyle(TVCdnHeaderButtonStyle(isFocused: headerFocused))
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
                            onSelect(cdnIndex, urlIndex)
                        } label: {
                            HStack(spacing: 14) {
                                Text(RoomPlaybackResolver.qualityDisplayTitle(quality, in: playArgs))
                                    .font(.system(size: 28, weight: (selected || isFocused) ? .semibold : .regular))
                                    .foregroundStyle(selected ? .white : .white.opacity(isFocused ? 0.95 : 0.8))

                                Spacer()

                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.2)
                                          : isFocused ? .white.opacity(0.25)
                                          : .clear)
                            )
                        }
                        .buttonStyle(TVQualityItemButtonStyle(isFocused: isFocused))
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
            Text(cdn.cdn.isEmpty ? "线路 \(cdnIndex + 1)" : cdn.cdn)
                .font(.system(size: 22, weight: .semibold))

            if isCurrentCdn {
                Text("当前")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }

            Spacer()

            if canCollapse {
                Text("\(cdn.qualitys.count) 个清晰度")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.4))

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.horizontal, canCollapse ? 16 : 0)
        .padding(.vertical, canCollapse ? 14 : 0)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private var normalizedQualityTitle: String? {
        let trimmed = viewModel.currentPlayQualityString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "清晰度" else { return nil }
        return trimmed
    }
}


// MARK: - tvOS Button Styles

/// 清晰度选项按钮样式：聚焦时微缩放 + 高亮
private struct TVQualityItemButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

/// 关闭按钮样式：圆形 glass 背景 + 聚焦缩放
private struct TVPanelCloseButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.white.opacity(isFocused ? 0.3 : 0.1))
            }
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

/// CDN 线路标题按钮样式：聚焦时高亮背景
private struct TVCdnHeaderButtonStyle: ButtonStyle {
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isFocused ? .white.opacity(0.15) : .clear)
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}
