//
//  MoreActionsButton.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import AVKit

private enum MoreActionsSheet: String, Identifiable {
    case streamerInfo
    case subtitleTranslation

    var id: String { rawValue }
}

/// 直播间功能按钮（清屏、主播详情等直播间相关功能）
struct MoreActionsButton: View {
    let room: LiveModel
    var onClearChat: () -> Void
    var showQualityOption: Bool = false
    var onShowQualityPanel: (() -> Void)? = nil
    var onRefreshPlayback: (() -> Void)? = nil
    var supportsPictureInPicture: Bool = false
    var onTogglePictureInPicture: (() -> Void)? = nil
    var usesDetailPill = false
    var showsDanmakuConnectionIssue = false
    var onJumpToLatestChat: (() -> Void)?
    var usesSharedPlayerGlass = false
    var popupPresented: Binding<Bool>?

    @Environment(RoomInfoViewModel.self) private var viewModel
    @State private var presentedSheet: MoreActionsSheet?
    @State private var buttonPressed = false
    @State private var showSubtitleLanguages = false
    @State private var subtitleActivationID = UUID()
    @State private var presentedDanmakuIssue: String?

    private var danmakuIssue: String? {
        showsDanmakuConnectionIssue ? viewModel.danmakuConnectionIssue : nil
    }

    private var isDanmakuIssuePresented: Binding<Bool> {
        Binding(
            get: { presentedDanmakuIssue != nil },
            set: { if !$0 { presentedDanmakuIssue = nil } }
        )
    }

    var body: some View {
        ZStack {
            Menu {
                Button("主播详情") {
                    presentedSheet = .streamerInfo
                }

                if showQualityOption {
                    Button("清晰度 - \(viewModel.currentPlayQualityString)") {
                        onShowQualityPanel?()
                    }
                }

                if let onRefreshPlayback {
                    Button("刷新直播") {
                        onRefreshPlayback()
                    }
                    .disabled(viewModel.isLoading)
                }

                if supportsPictureInPicture, let onTogglePictureInPicture {
                    Button("画中画") {
                        onTogglePictureInPicture()
                    }
                }

                if let danmakuIssue {
                    Button("弹幕连接详情") {
                        presentedDanmakuIssue = danmakuIssue
                    }
                }

                Menu("实时字幕") {
                    LiveSubtitleQuickControls(playback: viewModel.subtitlePlayback) {
                        subtitleActivationID = viewModel.subtitlePlayback.activationID
                        showSubtitleLanguages = true
                    }

                    Button("翻译与字幕设置…") {
                        presentedSheet = .subtitleTranslation
                    }
                }

                // MARK: - Legacy Quality Menu (commented out for rollback)
                /*
                if showQualityOption, let playArgs = viewModel.currentRoomPlayArgs {
                    Menu("清晰度 - \(viewModel.currentPlayQualityString)") {
                        ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                            Menu(PlaybackDisplay.lineTitle(for: cdn, index: cdnIndex)) {
                                ForEach(Array(cdn.qualitys.enumerated()), id: \.offset) { urlIndex, quality in
                                    Button {
                                        viewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex, selectionOrigin: .user)
                                    } label: {
                                        HStack {
                                            Text(quality.title)
                                            if viewModel.currentCdnIndex == cdnIndex && viewModel.currentQualityIndex == urlIndex {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                */

                if let onJumpToLatestChat {
                    Button("查看最新评论", action: onJumpToLatestChat)
                }

                Button("清屏") {
                    onClearChat()
                }
            } label: {
                if usesDetailPill {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: FullUIPlayerDetailChrome.pillHeight, height: FullUIPlayerDetailChrome.pillHeight)
                        .background(FullUIPlayerDetailChrome.pillFill, in: Circle())
                        .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                        .contentShape(Rectangle())
                } else if usesSharedPlayerGlass {
                    menuGlyph
                } else {
                    menuGlyph
                        .fullUIPlayerCircularControl()
                        .environment(\.colorScheme, .dark)
                }
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("更多直播间操作")
            .accessibilityValue(danmakuIssue == nil ? Text("") : Text("弹幕连接异常"))
        }
        .roomPlayerSheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .streamerInfo:
                StreamerInfoSheet(room: room)
            case .subtitleTranslation:
                NavigationStack {
                    TranslationSettingView()
                        .playerSheetNavigation(Text("翻译与字幕")) { presentedSheet = nil }
                }
            }
        }
        .roomPlayerSheet(isPresented: $showSubtitleLanguages, initialDetent: .medium) {
            LiveSubtitleLanguageSelectionSheet(
                playback: viewModel.subtitlePlayback,
                activationID: subtitleActivationID
            )
        }
        .alert("弹幕连接", isPresented: isDanmakuIssuePresented, presenting: presentedDanmakuIssue) { _ in
            Button("好", role: .cancel) {}
        } message: { issue in
            Text(issue)
        }
        .onChange(of: viewModel.subtitlePlayback.activationID) { _, _ in
            showSubtitleLanguages = false
        }
        .onChange(of: presentedSheet != nil || showSubtitleLanguages || presentedDanmakuIssue != nil) { _, presented in
            popupPresented?.wrappedValue = presented
        }
    }

    private var menuGlyph: some View {
        Image(systemName: "ellipsis")
            .font(FullUIPlayerChrome.symbolFont)
            .foregroundStyle(.white)
            .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if danmakuIssue != nil {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                        .padding(9)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

#Preview {
    let room = LiveModel(
        userName: "测试主播",
        roomTitle: "测试直播间",
        roomCover: "",
        userHeadImg: "",
        liveType: .placeholder,
        liveState: "1",
        userId: "123",
        roomId: "456",
        liveWatchedCount: "1000"
    )
    ZStack {
        Color.black
        MoreActionsButton(
            room: room,
            onClearChat: {
                Logger.debug("清屏", category: .ui)
            }
        )
    }
    .environment(RoomInfoViewModel(room: room))
}
