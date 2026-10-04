//
//  PlatformAccountLoginView.swift
//  AngelLive
//
//  数据驱动的平台账号登录列表。
//  所有平台信息与登录方式来自 PlatformLoginRegistry，不再硬编码。
//

import SwiftUI
import AngelLiveCore

struct PlatformAccountLoginView: View {
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.dismiss) private var dismiss
    private let recoveryPluginIDs: [String]?
    @State private var platforms: [LoginPlatformEntry] = []
    @State private var platformsLoaded = false
    @State private var methodSelection: LoginPlatformEntry?
    @State private var selectedLogin: LoginPresentation?
    @State private var pendingLogin: LoginPresentation?
    @State private var accountSelection: LoginPlatformEntry?
    @State private var pendingMethodSelection: LoginPlatformEntry?
    @State private var openingAccount = false
    @State private var didAutoOpenRecovery = false

    private struct LoginPresentation: Identifiable {
        let entry: LoginPlatformEntry
        let method: PlatformLoginMethod
        let startsWithLogin: Bool
        var id: String { "\(entry.pluginId):\(method.rawValue)" }

        init(entry: LoginPlatformEntry, method: PlatformLoginMethod, startsWithLogin: Bool = false) {
            self.entry = entry
            self.method = method
            self.startsWithLogin = startsWithLogin
        }
    }

    init(recoveryPluginIDs: [String]? = nil) {
        self.recoveryPluginIDs = recoveryPluginIDs
    }

    var body: some View {
        List {
            Section {
                if recoveryPluginIDs != nil, !platformsLoaded {
                    ProgressView("正在读取登录方式…")
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else if recoveryPluginIDs != nil, platforms.isEmpty {
                    ErrorView.empty(
                        title: "暂无可用登录方式",
                        message: recoveryPluginIDs?.isEmpty == true
                            ? "当前没有已安装且可登录的平台。"
                            : "目标插件可能已卸载，或没有声明此设备可用的登录方式。",
                        symbolName: "person.crop.circle.badge.xmark",
                        tint: .secondary
                    )
                } else {
                    ForEach(platforms) { entry in
                    Button {
                        openingAccount = true
                        Task {
                            if recoveryPluginIDs != nil {
                                selectLoginMethod(entry)
                            } else {
                                await openAccount(entry)
                            }
                            openingAccount = false
                        }
                    } label: {
                        HStack(spacing: 12) {
                            platformIcon(entry: entry)
                                .frame(width: 24, height: 24)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                Text(loginMethodDescription(for: entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if recoveryPluginIDs != nil {
                                EmptyView()
                            } else if entry.supportsAPICredentials {
                                PlatformAPITokenStatusLabel(pluginId: entry.pluginId).font(.caption)
                            } else {
                                let loggedIn = syncService.isLoggedIn(pluginId: entry.pluginId)
                                Text(loggedIn ? "已登录" : "未登录")
                                    .font(.caption)
                                    .foregroundStyle(loggedIn ? AppConstants.Colors.success : .secondary)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(openingAccount)
                    }
                }
            } header: {
                Text(recoveryPluginIDs == nil ? "平台列表" : "选择登录平台")
            } footer: {
                if recoveryPluginIDs == nil {
                    Text("凭据由宿主安全保存，仅提供给对应插件用于登录验证和鉴权，不会与其他插件共享。")
                } else if recoveryPluginIDs?.isEmpty == true {
                    Text("请选择需要恢复登录的平台。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(recoveryPluginIDs == nil ? "平台账号登录" : "登录平台")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if recoveryPluginIDs != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            await loadPlatforms()
            guard let recoveryPluginIDs else {
                await syncService.refreshAllLoginStatus()
                return
            }
            guard !didAutoOpenRecovery,
                  recoveryPluginIDs.count == 1,
                  platforms.count == 1,
                  let entry = platforms.first else { return }
            didAutoOpenRecovery = true
            selectLoginMethod(entry)
        }
        .sheet(item: $methodSelection, onDismiss: {
            // Start the chosen flow after the selection panel has fully closed.
            selectedLogin = pendingLogin
            pendingLogin = nil
        }) { entry in
            LoginMethodSelectionSheet(entry: entry) { method in
                pendingLogin = LoginPresentation(
                    entry: entry,
                    method: method,
                    startsWithLogin: recoveryPluginIDs != nil
                )
                methodSelection = nil
            }
        }
        .sheet(item: $selectedLogin, onDismiss: {
            Task {
                await syncService.refreshAllLoginStatus()
            }
        }) { selection in
            PlatformLoginSheet(
                entry: selection.entry,
                method: selection.method,
                startsWithLogin: selection.startsWithLogin
            )
        }
        .sheet(item: $accountSelection, onDismiss: {
            if let entry = pendingMethodSelection {
                pendingMethodSelection = nil
                selectLoginMethod(entry)
            }
        }) { entry in
            PlatformAPIAccountView(entry: entry) {
                pendingMethodSelection = entry
                accountSelection = nil
            }
        }
    }

    private func openAccount(_ entry: LoginPlatformEntry) async {
        if entry.supportsAPICredentials {
            let service = PlatformAPITokenService.shared
            await service.load(pluginId: entry.pluginId)
            if service.statuses[entry.pluginId] != nil || service.failures[entry.pluginId] != nil {
                accountSelection = entry
                return
            }
        }
        if syncService.isLoggedIn(pluginId: entry.pluginId) {
            selectedLogin = LoginPresentation(entry: entry, method: .web)
            return
        }
        selectLoginMethod(entry)
    }

    private func selectLoginMethod(_ entry: LoginPlatformEntry) {
        let methods = entry.methods(for: .iOS)
        if methods.count > 1 {
            methodSelection = entry
        } else if let method = methods.first {
            selectedLogin = LoginPresentation(
                entry: entry,
                method: method,
                startsWithLogin: recoveryPluginIDs != nil
            )
        }
    }

    private func loadPlatforms() async {
        let all = await PlatformLoginRegistry.shared.availablePlatforms()
        let installed = all.filter { pluginAvailability.isPluginInstalled(for: $0.pluginId) }
        if let recoveryPluginIDs, !recoveryPluginIDs.isEmpty {
            let candidates = Set(recoveryPluginIDs)
            platforms = installed.filter { candidates.contains($0.pluginId) }
        } else {
            platforms = installed
        }
        platformsLoaded = true
    }

    private func loginMethodDescription(for entry: LoginPlatformEntry) -> String {
        entry.methods(for: .iOS).map(\.iOSDisplayTitle).joined(separator: " / ")
    }

    @ViewBuilder
    private func platformIcon(entry: LoginPlatformEntry) -> some View {
        if let liveType = LiveType(rawValue: entry.liveType),
           let image = PlatformIconProvider.pluginManagementImage(for: liveType) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LoginMethodSelectionSheet: View {
    let entry: LoginPlatformEntry
    let onSelect: (PlatformLoginMethod) -> Void
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric private var rowHeight: CGFloat = 56
    @ScaledMetric private var surroundingHeight: CGFloat = 208

    var body: some View {
        let methods = entry.methods(for: .iOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择登录方式")
                        .font(.title2.bold())
                    Text(entry.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(methods) { method in
                        Button { onSelect(method) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: symbol(for: method))
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 32)
                                    .accessibilityHidden(true)
                                Text(method == .deviceCode ? "登录 \(entry.displayName)" : method.iOSDisplayTitle)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if method != methods.last {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                Button(role: .cancel) { dismiss() } label: {
                    Text("取消")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(surroundingHeight + rowHeight * CGFloat(methods.count)), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func symbol(for method: PlatformLoginMethod) -> String {
        switch method {
        case .deviceCode: "key.viewfinder"
        case .clientCredentials: "key.horizontal.fill"
        case .apiToken: "key.fill"
        case .qrCode: "qrcode.viewfinder"
        case .web: "globe"
        case .manualCookie: "doc.on.clipboard"
        }
    }
}

private extension PlatformLoginMethod {
    var iOSDisplayTitle: String {
        self == .apiToken ? "手动填写 Access Token" : title
    }
}

#Preview {
    NavigationStack {
        PlatformAccountLoginView()
    }
}
