import AngelLiveCore
import Kingfisher
import SwiftUI
import UIKit

extension View {
    func tvPlayerGlass(in shape: some Shape, interactive: Bool = true) -> some View {
        modifier(TVPlayerGlassModifier(shape: shape, interactive: interactive))
    }

    func tvPlayerMediaText() -> some View {
        modifier(TVPlayerMediaTextModifier())
    }
}

struct TVLivePlayerRoomIdentity: View {
    let room: LiveModel
    var translatesTitle = true

    var body: some View {
        if translatesTitle {
            identity.roomTitleTranslationTask(room.roomTitle)
        } else {
            identity
        }
    }

    private var identity: some View {
        HStack(spacing: 14) {
            Group {
                if room.userHeadImg.isEmpty {
                    avatarPlaceholder
                } else {
                    KFImage(URL(string: room.userHeadImg))
                        .placeholder { avatarPlaceholder }
                        .resizable()
                }
            }
            .scaledToFill()
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if !room.userName.isEmpty {
                    TVPlayerName(name: room.userName, font: .systemFont(ofSize: 38, weight: .semibold))
                }
                let title = translatesTitle ? RoomTitleTranslationService.shared.displayTitle(for: room.roomTitle) : room.roomTitle
                if !title.isEmpty {
                    Text(verbatim: title)
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.white.opacity(0.7))
    }
}

private struct TVPlayerGlassModifier<GlassShape: Shape>: ViewModifier {
    let shape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(tvOS 26.0, *) {
            let glass = Glass.regular.tint(.black.opacity(0.45)).interactive(interactive)
            content.glassEffect(glass, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

private struct TVPlayerMediaTextModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.85), radius: 3, y: 1)
            .background {
                if contrast == .increased {
                    Color.clear
                        .tvPlayerGlass(in: Capsule(), interactive: false)
                        .padding(.horizontal, -4)
                        .padding(.vertical, -2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

struct TVPlayerName: View {
    let name: String
    let font: UIFont
    var maximumWidth: CGFloat? = nil

    var body: some View {
        let displayName = BracketSafeName(name)
        let idealWidth = ceil((displayName.fullTitle as NSString).size(withAttributes: [.font: font]).width)
        Text(verbatim: displayName.fullTitle)
            .font(Font(font))
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: max(0, min(idealWidth, maximumWidth ?? idealWidth)))
            .overlay {
                GeometryReader { geometry in
                    let fitted = displayName.title { candidate in
                        (candidate as NSString).size(withAttributes: [.font: font]).width <= geometry.size.width + 0.5
                    }
                    Text(verbatim: fitted)
                        .font(Font(font))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
    }
}
