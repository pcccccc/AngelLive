import SwiftUI

/// Adapts SwiftUX's grouped settings row pattern: one identity and one row
/// structure, with the trailing content determined by the operation state.
public struct PluginManagementPluginRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let name: String
    let version: String
    let requiresLogin: Bool
    let state: RemotePluginCatalogActionState
    let icon: Image?
    let disabled: Bool
    let isWaiting: Bool
    let action: () -> Void

    public init(name: String, version: String, requiresLogin: Bool,
                state: RemotePluginCatalogActionState, icon: Image? = nil,
                disabled: Bool, isWaiting: Bool = false, action: @escaping () -> Void) {
        self.name = name
        self.version = version
        self.requiresLogin = requiresLogin
        self.state = state
        self.icon = icon
        self.disabled = disabled
        self.isWaiting = isWaiting
        self.action = action
    }

    public var body: some View {
        #if os(tvOS)
        Button(action: action) {
            content
                .padding(.vertical, 16)
        }
        .disabled(disabled)
        #else
        #if os(macOS)
        content
            .padding(.vertical, 12)
        #else
        content
            .padding(.vertical, 6)
        #endif
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if dynamicTypeSize.isAccessibilitySize {
            verticalContent
        } else {
            ViewThatFits(in: .horizontal) {
                horizontalContent
                verticalContent
            }
        }
        #else
        horizontalContent
        #endif
    }

    private var horizontalContent: some View {
        HStack(alignment: rowAlignment, spacing: 12) {
            iconView
            detailsView
            Spacer(minLength: 10)
            actionView
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                iconView
                detailsView
                Spacer(minLength: 0)
            }
            HStack {
                Spacer(minLength: 0)
                actionView
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        Group {
            if let icon {
                icon.resizable().scaledToFit().padding(5)
            } else {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: iconSize, height: iconSize)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(requiresLogin ? "\(version) ·" : version)
                    .fixedSize(horizontal: false, vertical: true)
                if requiresLogin {
                    Image(systemName: "person.crop.circle")
                    Text("需登录")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if case .failed(let reason) = state {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .layoutPriority(1)
    }

    private var actionView: some View {
        PluginManagementRowAction(
            name: name,
            state: state,
            disabled: disabled,
            isWaiting: isWaiting,
            action: action
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rowAlignment: VerticalAlignment {
        #if os(macOS)
        .center
        #else
        .top
        #endif
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        64
        #elseif os(macOS)
        36
        #else
        46
        #endif
    }
}

private struct PluginManagementRowAction: View {
    let name: String
    let state: RemotePluginCatalogActionState
    let disabled: Bool
    let isWaiting: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isWaiting {
                Text("等待更新", bundle: .main)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                switch state {
                case .installing, .updating:
                    ProgressView().controlSize(.small)
                    Text(state == .updating ? "更新中" : "安装中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .installed:
                    #if os(tvOS)
                    Text("已安装", bundle: Bundle.main)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                case .install, .update, .failed:
                    #if os(tvOS)
                    Text(actionTitle).font(.callout)
                    #else
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(disabled)
                    .accessibilityLabel(actionAccessibilityLabel)
                    #endif
                }
            }
        }
    }

    private var actionTitle: LocalizedStringResource {
        switch state {
        case .install: .init("安装", bundle: .atURL(Bundle.main.bundleURL))
        case .failed: .init("重试", bundle: .atURL(Bundle.main.bundleURL))
        default: .init("更新", bundle: .atURL(Bundle.main.bundleURL))
        }
    }

    private var actionAccessibilityLabel: String {
        switch state {
        case .install: "安装 \(name)"
        case .update: "更新 \(name)"
        case .failed: "重试安装或更新 \(name)"
        default: name
        }
    }
}
