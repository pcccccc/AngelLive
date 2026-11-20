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
    var verticalCenter = Self.detailCenter

    static let detailCenter: CGFloat = 0.5
    static let portraitCenter: CGFloat = 0.63
    static let fade = Animation.easeOut(duration: 0.2)

    var body: some View {
        GeometryReader { geometry in
            let centerY = geometry.size.height * verticalCenter
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

/// Resizes the existing loading screen as a viewport so the cover stays cropped
/// and text can reflow at its normal size throughout the move to the small player.
struct PlayerEntryLoadingViewport: View, Animatable {
    let room: LiveModel
    let diagnostics: PlayerLoadingDiagnostics
    let size: CGSize
    let safeArea: EdgeInsets
    let playerHeight: CGFloat
    var detailProgress: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    var animatableData: CGFloat {
        get { detailProgress }
        set { detailProgress = newValue }
    }

    var body: some View {
        let full = 1 - min(1, max(0, detailProgress))
        let fullHeight = size.height + safeArea.top + safeArea.bottom
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        PlayerLoadingScreen(
            room: room, diagnostics: diagnostics,
            verticalCenter: PlayerLoadingScreen.detailCenter
                + full * (PlayerLoadingScreen.portraitCenter - PlayerLoadingScreen.detailCenter)
        )
        .frame(
            width: size.width + full * (safeArea.leading + safeArea.trailing),
            height: playerHeight + full * (fullHeight - playerHeight)
        )
        .offset(x: -direction * full * safeArea.leading, y: -full * safeArea.top)
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
