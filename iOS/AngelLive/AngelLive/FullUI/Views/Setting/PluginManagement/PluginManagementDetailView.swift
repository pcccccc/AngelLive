import SwiftUI
import AngelLiveCore

struct PluginManagementDetailView: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(PluginInstallConsentService.self) private var consent
    @Environment(PluginManagementFeedback.self) private var feedback
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var credentials = PlatformCredentialSyncService.shared
    let item: ManagedPluginItem
    let canOperate: Bool
    let consentHostID: UUID
    let action: (UUID) -> Void
    let uninstall: (String) -> Void
    @State private var features: [PlatformFeature] = []
    @State private var showsLogin = false
    private var version: String { manager.installedVersion(for: item.pluginID) ?? item.remote?.item.version ?? "未知" }
    private var installed: Bool { manager.installedVersion(for: item.pluginID) != nil }
    private var needsLogin: Bool { availability.requiresLogin(for: item.pluginID) || item.remote?.item.auth?.required == true }
    private var state: RemotePluginCatalogActionState { manager.managementActionState(for: item.pluginID, remote: item.remote) }
    private var verifiedCurrent: Bool {
        guard let source = item.sourceURL, item.remote != nil,
              manager.latestVersion(for: item.pluginID) != nil,
              !manager.hasUpdate(for: item.pluginID),
              case .healthy = manager.health(for: source) else { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(spacing: PluginManagementLayout.detailSpacing) {
                PluginDetailHero(item: item)
                VStack(spacing: 8) {
                    PluginActionButton(item: item, canOperate: canOperate, large: true, action: action)
                    if let reason = item.installationFailure(in: manager) {
                        PluginInstallationFailureReason(reason: reason)
                    } else if state == .installed, item.namespace == .installed, !feedback.recentSuccessIDs.contains(item.pluginID) {
                        if verifiedCurrent {
                            Label {
                                Text("已是最新版本").foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }.font(.subheadline)
                        } else {
                            Text("当前版本 \(version)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.horizontal, 8)
                PluginDetailInformation(pluginName: item.name, version: version, capabilityCount: features.isEmpty ? nil : features.count, needsLogin: needsLogin, loggedIn: credentials.isLoggedIn(pluginId: item.pluginID), canLogin: installed) { showsLogin = true }
                if !features.isEmpty { PluginDetailCapabilities(features: features) }
                if installed {
                    if !canOperate && !manager.isPendingInstallation(for: item.pluginID) {
                        Text("正在处理插件，完成后可以卸载。").font(.footnote).foregroundStyle(.secondary)
                    }
                    PluginInlineRemoval(
                        title: "卸载插件",
                        message: "将移除「\(item.name)」及其本地数据。卸载后 5 秒内可以撤销。",
                        confirmationTitle: "卸载", disabled: !canOperate,
                        remove: { uninstall(item.pluginID) }
                    )
                }
            }.padding(.horizontal, PluginManagementLayout.pageInset).padding(.top, PluginManagementLayout.iconTextSpacing).padding(.bottom, PluginManagementLayout.contentInset * 2)
                .frame(maxWidth: PluginManagementLayout.readingWidth).frame(maxWidth: .infinity)
        }
        .background(PluginManagementLayout.pageBackground)
        .tint(PluginManagementLayout.primaryAction)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("关闭", systemImage: "xmark") { dismiss() }
                    .disabled(consent.isPresenting(for: consentHostID))
            }
        }
        .task(id: availability.catalogRevision) {
            features = PlatformCapability.declaredFeatures(forPluginId: item.pluginID) ?? []
        }
        .sheet(isPresented: $showsLogin) {
            NavigationStack { PlatformAccountLoginView(recoveryPluginIDs: [item.pluginID]) }
        }
    }
}

private struct PluginDetailHero: View {
    let item: ManagedPluginItem
    var body: some View {
        VStack(spacing: 6) {
            PluginManagementIcon(pluginID: item.pluginID, displayName: item.name, remoteIcon: item.remote?.item.icon, size: PluginManagementLayout.iconSize * 2).padding(.bottom, 8)
            Text(item.name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Group {
                if let host = item.sourceURL.flatMap({ URL(string: $0)?.host() }) {
                    Text("来自 \(host)")
                } else {
                    Text("本地插件")
                }
            }.font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }
}

private struct PluginDetailInformation: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    let pluginName: String
    let version: String
    let capabilityCount: Int?
    let needsLogin: Bool
    let loggedIn: Bool
    let canLogin: Bool
    let login: () -> Void
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    PluginDetailStat(title: "版本", value: version)
                    Divider()
                    if let capabilityCount {
                        PluginDetailStat(title: "能力", value: String(localized: "\(capabilityCount) 项", locale: locale))
                        Divider()
                    }
                    account
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    PluginDetailStat(title: "版本", value: version)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .overlay(alignment: .trailing) { separator }
                    if let capabilityCount {
                        PluginDetailStat(title: "能力", value: String(localized: "\(capabilityCount) 项", locale: locale))
                            .frame(maxHeight: .infinity, alignment: .top)
                            .overlay(alignment: .trailing) { separator }
                    }
                    account.frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, PluginManagementLayout.summaryVerticalInset).padding(.horizontal, 6)
            .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
    }

    private var account: some View {
        Group {
            if needsLogin && !loggedIn && canLogin {
                Button(action: login) {
                    PluginDetailStat(title: "账号", value: "登录", isAction: true)
                        .frame(maxHeight: typeSize.isAccessibilitySize ? nil : .infinity, alignment: .top)
                        .contentShape(Rectangle())
                }.buttonStyle(PluginPressButtonStyle()).accessibilityLabel("登录 \(pluginName) 账号")
            } else {
                PluginDetailStat(title: "账号", value: needsLogin ? (loggedIn ? "已登录" : "安装后登录") : "不需要")
            }
        }.frame(maxWidth: .infinity, alignment: .top)
    }

    private var separator: some View {
        Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5).padding(.vertical, 2)
            .accessibilityHidden(true)
    }
}

private struct PluginDetailStat: View {
    let title: LocalizedStringKey
    let value: String
    var isAction = false
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(isAction ? PluginManagementLayout.primaryAction : .primary)
                .lineLimit(1).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }.multilineTextAlignment(.center).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
    }
}

private struct PluginDetailCapabilities: View {
    let features: [PlatformFeature]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PluginManagementEdgeText(text: "支持", style: .headline)
            PluginCapabilityFlow {
                ForEach(features, id: \.rawValue) { feature in
                    Text(feature.displayName).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
            }.padding(PluginManagementLayout.contentInset).frame(maxWidth: .infinity, alignment: .leading)
                .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
        }
    }
}

private struct PluginCapabilityFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: ProposedViewSize(width: min(bounds.width, subviews[index].sizeThatFits(.unspecified).width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + 8; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + 8; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}

struct PluginInlineRemoval: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: LocalizedStringKey
    let message: String
    let confirmationTitle: LocalizedStringKey
    let disabled: Bool
    var offersAssociatedRemoval = false
    var removeAssociated: ((Bool) -> Void)?
    let remove: () -> Void
    @State private var confirming = false
    @State private var includesAssociated = false
    var body: some View {
        VStack(spacing: 12) {
            if confirming {
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if offersAssociatedRemoval { Toggle("同时卸载仅由此来源提供的插件", isOn: $includesAssociated).font(.subheadline) }
                HStack(spacing: 8) {
                    Button { confirming = false } label: {
                        Text("取消").frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }.foregroundStyle(.primary)
                    Button(role: .destructive) {
                        if let removeAssociated { removeAssociated(includesAssociated) } else { remove() }
                    } label: {
                        Text(confirmationTitle).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(.white).background(Color.red, in: Capsule())
                    }
                }.font(.body.weight(.semibold)).buttonStyle(PluginPressButtonStyle())
            } else {
                Button(title, role: .destructive) { confirming = true }.frame(maxWidth: .infinity, minHeight: 44)
            }
        }.padding(confirming ? PluginManagementLayout.contentInset : PluginManagementLayout.collapsedRemovalInset).frame(maxWidth: .infinity)
            .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
            .disabled(disabled)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4), value: confirming)
    }
}
