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

    let bridge: PlayerControlBridge
    @Binding var showVideoSetting: Bool
    @Binding var showDanmakuSettings: Bool

    var body: some View {
        ZStack {
            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(12)

            if !bridge.isPlaying {
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
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
                KSOptions.supportedInterfaceOrientations = .portrait
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

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

                SettingsButton(
                    showVideoSetting: $showVideoSetting,
                    showDanmakuSettings: $showDanmakuSettings,
                    onDismiss: { dismiss() },
                    onPopupStateChanged: { _ in }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.35), in: Capsule())
        }
    }

    private var bottomBar: some View {
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
            .background(.black.opacity(0.35), in: Capsule())

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
            .background(.black.opacity(0.35), in: Capsule())
        }
    }

    private var qualityMenu: some View {
        Menu {
            if let playArgs = viewModel.currentRoomPlayArgs {
                ForEach(Array(playArgs.enumerated()), id: \.offset) { cdnIndex, cdn in
                    Menu {
                        ForEach(Array(cdn.qualitys.enumerated()), id: \.offset) { urlIndex, quality in
                            Button {
                                viewModel.changePlayUrl(cdnIndex: cdnIndex, urlIndex: urlIndex)
                            } label: {
                                HStack {
                                    Text(quality.title)
                                    if viewModel.currentCdnIndex == cdnIndex && viewModel.currentPlayQualityQn == quality.qn {
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

    private var fullscreenIconName: String {
        if AppConstants.Device.isIPad {
            return isIPadFullscreen.wrappedValue ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        }
        return isCurrentLandscape ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
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

        let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
            interfaceOrientations: targetOrientation
        )

        windowScene.requestGeometryUpdate(geometryPreferences) { error in
            print("❌ 方向更新失败: \(error)")
        }

        if let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController {
            rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
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
}
