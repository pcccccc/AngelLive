import SwiftUI

/// Adapts SwiftUX's grouped settings row pattern: one identity and one row
/// structure, with the trailing content determined by the operation state.
public struct PluginManagementPluginRow: View {
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
        content.padding(.vertical, 6)
        #endif
    }

    private var content: some View {
        HStack(spacing: 14) {
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

            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(version).font(.caption).foregroundStyle(.secondary)
                if requiresLogin {
                    Label("需登录", systemImage: "person.crop.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if case .failed(let reason) = state {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            PluginManagementRowAction(state: state, disabled: disabled, isWaiting: isWaiting, action: action)
        }
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        64
        #else
        42
        #endif
    }
}

private struct PluginManagementRowAction: View {
    let state: RemotePluginCatalogActionState
    let disabled: Bool
    let isWaiting: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isWaiting {
                Text("等待更新", bundle: .main).font(.caption).foregroundStyle(.secondary)
            } else {
                switch state {
                case .installing, .updating:
                    ProgressView().controlSize(.small)
                    #if os(tvOS)
                    Text(state == .updating ? "更新中" : "安装中").font(.caption)
                    #endif
                case .installed:
                    Text("已安装", bundle: Bundle.main).font(.caption).foregroundStyle(.secondary)
                case .install, .update, .failed:
                    #if os(tvOS)
                    Text(actionTitle).font(.callout)
                    #else
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                            #if os(iOS)
                            .frame(minWidth: 38, minHeight: 28)
                            #endif
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(disabled)
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
}
