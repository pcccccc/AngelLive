import AngelLiveCore
import AngelLiveDependencies
import Kingfisher
import SharedAssets
import SwiftUI

struct MacPlayerLoadingScreen: View {
    let room: LiveModel
    let stage: PlaybackStartupStage
    let dynamicInfo: DynamicInfo?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if !room.roomCover.isEmpty, let url = URL(string: room.roomCover) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .scaleEffect(1.04)
                        .blur(radius: 12)
                        .accessibilityHidden(true)
                    Color.black.opacity(0.48)
                }

                ViewThatFits(in: .vertical) {
                    loadingContent(showsTitle: true, showsAvatar: true)
                    loadingContent(showsTitle: false, showsAvatar: true)
                    loadingContent(showsTitle: false, showsAvatar: false)
                }
                .padding(.horizontal, 24)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("player.loading")
            }
            .clipped()
        }
        .environment(\.colorScheme, .dark)
    }

    private func loadingContent(showsTitle: Bool, showsAvatar: Bool) -> some View {
        VStack(spacing: 8) {
            if showsAvatar { avatar }

            Text(room.userName.orDash)
                .font(.headline)
                .lineLimit(1)

            if showsTitle {
                TranslatedRoomTitle(room.roomTitle.orDash)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }

            ArcSpinner(size: 24, lineWidth: 1.5)
                .tint(.white)
                .padding(.top, 6)
                .accessibilityHidden(true)

            HStack(spacing: 4) {
                Text(stage.title)
                    .layoutPriority(1)
                if let dynamicInfo {
                    MacPlayerLoadingSpeed(info: dynamicInfo)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var avatar: some View {
        if !room.userHeadImg.isEmpty, let url = URL(string: room.userHeadImg) {
            KFImage(url)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .background { avatarPlaceholder }
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.fill")
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct MacPlayerLoadingSpeed: View {
    @ObservedObject var info: DynamicInfo

    var body: some View {
        if let bytes = Int64(exactly: info.networkSpeed.rounded(.towardZero)), bytes > 0 {
            let (value, unit) = SpeedFormatter.split(bytesPerSecond: bytes)
            Text("· \(value) \(unit)")
                .monospacedDigit()
        }
    }
}
