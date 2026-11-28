import SwiftUI

/// FullUI player drawers share their chrome, while each player owns its overlay and dismissal.
struct MacPlayerDrawer<Subtitle: View, Content: View>: View {
    let title: LocalizedStringKey
    let onClose: () -> Void
    @ViewBuilder let subtitle: () -> Subtitle
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    subtitle()
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer(minLength: 0)
                PanelCloseButton(closesOnEscape: true, expandsHitTarget: true, action: onClose)
                    .accessibilityLabel("关闭")
                    .help("关闭")
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .adaptiveGlassEffectRoundedRect(cornerRadius: 24)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    func macPlayerDrawerPlacement(in size: CGSize, width: CGFloat? = nil) -> some View {
        let inset = MacPlayerChrome.inset
        let drawerWidth = width ?? min(380, max(0, size.width - 2 * inset))
        return frame(width: drawerWidth)
            .padding(.vertical, inset)
            .padding(.trailing, min(inset, max(0, size.width - drawerWidth)))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
