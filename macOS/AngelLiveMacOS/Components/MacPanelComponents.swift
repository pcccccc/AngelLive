import SwiftUI

/// 弹窗与面板标题栏共用的小圆底关闭按钮。
/// 所有弹窗共用此组件,避免样式各自漂移。
struct PanelCloseButton: View {
    let action: () -> Void
    /// 是否绑定 Esc 快捷键关闭(自带 dismiss 的 sheet/popover 无需开启)。
    private let closesOnEscape: Bool
    private let expandsHitTarget: Bool

    init(closesOnEscape: Bool = false, expandsHitTarget: Bool = false, action: @escaping () -> Void) {
        self.expandsHitTarget = expandsHitTarget
        self.closesOnEscape = closesOnEscape
        self.action = action
    }

    var body: some View {
        let glyph = Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .background(Color.primary.opacity(0.06), in: Circle())
        Button(action: action) {
            if expandsHitTarget {
                glyph.frame(width: 44, height: 44).contentShape(Rectangle())
            } else {
                glyph
            }
        }
        .buttonStyle(.plain)
        .padding(expandsHitTarget ? -11 : 0)
        .modifier(EscapeShortcut(enabled: closesOnEscape))
    }

    private struct EscapeShortcut: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled {
                content.keyboardShortcut(.escape, modifiers: [])
            } else {
                content
            }
        }
    }
}

struct PanelIconTile<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.55))
            content
        }
        .frame(width: 34, height: 34)
    }
}

struct PanelStatusBadge: View {
    let title: String
    let tint: Color

    init(_ title: String, tint: Color = .secondary) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

struct MacFullUIFormControls: ViewModifier {
    let usesFullUI: Bool

    func body(content: Content) -> some View {
        if usesFullUI {
            content.toggleStyle(.switch)
                .tint(AppConstants.Colors.accent)
        } else {
            content
        }
    }
}

struct MacSettingsSwitchRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            PanelNavigationRow(title: title, subtitle: subtitle, showsChevron: false) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color.gradient)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .toggleStyle(.switch)
        .tint(AppConstants.Colors.accent)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

struct PanelNavigationRow: View {
    let title: String
    let subtitle: String?
    let showsChevron: Bool
    private let titleStyle: AnyShapeStyle
    private let icon: AnyView
    private let titleAccessory: AnyView
    private let trailingContent: AnyView

    init<Icon: View, TitleAccessory: View, Trailing: View>(
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = true,
        titleColor: Color? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsChevron = showsChevron
        self.titleStyle = titleColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary)
        self.icon = AnyView(icon())
        self.titleAccessory = AnyView(titleAccessory())
        self.trailingContent = AnyView(trailing())
    }

    init<Icon: View, Trailing: View>(
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = true,
        titleColor: Color? = nil,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsChevron: showsChevron,
            titleColor: titleColor,
            icon: icon,
            titleAccessory: { EmptyView() },
            trailing: trailing
        )
    }

    init<Icon: View>(
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = true,
        titleColor: Color? = nil,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            showsChevron: showsChevron,
            titleColor: titleColor,
            icon: icon,
            titleAccessory: { EmptyView() },
            trailing: { EmptyView() }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            PanelIconTile {
                icon
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(titleStyle)

                    titleAccessory
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            trailingContent

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct PanelHintCard: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    init(title: String, message: String, systemImage: String, tint: Color = .accentColor) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PanelIconTile {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
