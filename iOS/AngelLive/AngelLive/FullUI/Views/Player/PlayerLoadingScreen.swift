import AngelLiveCore
import AngelLiveDependencies
import Kingfisher
import SharedAssets
import SwiftUI

struct PlayerLoadingDiagnostics {
    var stage: PlaybackStartupStage = .fetchingSource
    #if canImport(KSPlayer)
    var streamInfo: DynamicInfo?
    #endif

    init() {}

    @MainActor
    init(viewModel: RoomInfoViewModel, layer: KSPlayerLayer?) {
        stage = viewModel.startupStage
        #if canImport(KSPlayer)
        if stage != .fetchingSource, let url = viewModel.currentPlayURL, let layer, layer.url == url {
            streamInfo = layer.player.dynamicInfo
        }
        #endif
    }
}

struct PlayerLoadingScreen: View {
    let room: LiveModel
    var diagnostics = PlayerLoadingDiagnostics()
    var prefersLowerAlignment = false

    static let fade = Animation.easeOut(duration: 0.2)

    var body: some View {
        GeometryReader { geometry in
            let centerY = geometry.size.height * (prefersLowerAlignment ? 0.63 : 0.5)
            let contentHeight = 2 * min(centerY, geometry.size.height - centerY)

            ZStack {
                Color.black
                if !room.roomCover.isEmpty, let url = URL(string: room.roomCover) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .scaleEffect(1.04)
                        .blur(radius: 8)
                    Color.black.opacity(0.48)
                }

                ViewThatFits(in: .vertical) {
                    loadingContent(showsTitle: true, showsAvatar: true)
                    loadingContent(showsTitle: false, showsAvatar: true)
                    loadingContent(showsTitle: false, showsAvatar: false)
                }
                .padding(.horizontal, 24)
                .frame(width: geometry.size.width, height: contentHeight)
                .position(x: geometry.size.width / 2, y: centerY)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("player.loading")
            }
            .clipped()
        }
        .environment(\.colorScheme, .dark)
    }

    private func loadingContent(showsTitle: Bool, showsAvatar: Bool) -> some View {
        VStack(spacing: 8) {
            if showsAvatar {
                if !room.userHeadImg.isEmpty, let url = URL(string: room.userHeadImg) {
                    KFImage(url)
                        .placeholder { avatarPlaceholder }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else {
                    avatarPlaceholder
                }
            }

            Text(room.userName.orDash)
                .font(.headline)
                .lineLimit(1)
            if showsTitle {
                Text(room.roomTitle.orDash)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }
            ArcSpinner(size: 24, lineWidth: 1.5)
                .tint(.white)
                .padding(.top, 6)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(diagnostics.stage.title)
                    .layoutPriority(1)
                #if canImport(KSPlayer)
                if let info = diagnostics.streamInfo {
                    PlayerLoadingSpeed(info: info)
                }
                #endif
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.fill")
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

#if canImport(KSPlayer)
private struct PlayerLoadingSpeed: View {
    @ObservedObject var info: DynamicInfo

    var body: some View {
        let speed = Double(info.networkSpeed)
        if speed.isFinite, speed > 0 {
            let kilobytes = speed / 1024
            let rate = kilobytes < 1024
                ? String(format: "%.0f KB/s", kilobytes)
                : String(format: "%.1f MB/s", kilobytes / 1024)
            Text("· \(rate)")
                .monospacedDigit()
        }
    }
}
#endif
