//
//  MacAccountManagementView.swift
//  AngelLiveMacOS
//
//  设置二级页:平台账号管理。展示已安装平台并跳转登录 sheet。
//

import SwiftUI
import AngelLiveCore

struct MacAccountManagementView: View {
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    @State private var platforms: [LoginPlatformEntry] = []
    @State private var selectedLoginPluginId: String?

    var body: some View {
        Form {
            Section {
                PanelHintCard(
                    title: "登录后自动同步会话",
                    message: "凭据由宿主安全保存，仅提供给对应插件用于登录验证和鉴权，不会与其他插件共享。",
                    systemImage: "person.crop.circle.badge.checkmark",
                    tint: .blue
                )
            }

            Section {
                if !pluginAvailability.hasAvailablePlugins {
                    ErrorView.empty(
                        title: "暂无已安装插件",
                        message: "请先在「插件管理」中安装平台扩展，安装完成后这里会显示对应平台。",
                        symbolName: "puzzlepiece.extension",
                        tint: .secondary,
                        layout: .compact(minHeight: 180)
                    )
                } else if platforms.isEmpty {
                    ErrorView.empty(
                        title: "当前插件未配置网页登录",
                        message: "已安装的插件没有声明网页登录流程，无法在此页登录。",
                        symbolName: "person.crop.circle.badge.xmark",
                        tint: .secondary,
                        layout: .compact(minHeight: 180)
                    )
                } else {
                    ForEach(platforms) { entry in
                        platformAccountRow(entry)
                    }
                }
            } header: {
                Text("平台列表")
            } footer: {
                if !platforms.isEmpty {
                    Text("共 \(platforms.count) 个平台")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("账号管理")
        .task {
            await loadPlatforms()
            await syncService.refreshAllLoginStatus()
        }
        .sheet(item: selectedPlatformBinding, onDismiss: {
            Task { await syncService.refreshAllLoginStatus() }
        }) { entry in
            MacPlatformLoginSheet(
                entry: entry,
                isLoggedIn: syncService.isLoggedIn(pluginId: entry.pluginId)
            )
                .frame(minWidth: 800, minHeight: 600)
        }
    }

    private func platformAccountRow(_ entry: LoginPlatformEntry) -> some View {
        Button {
            selectedLoginPluginId = entry.pluginId
        } label: {
            PanelNavigationRow(
                title: entry.displayName,
                subtitle: loginMethodDescription(for: entry)
            ) {
                if let liveType = LiveType(rawValue: entry.liveType),
                   let icon = MacPlatformIconProvider.tabImage(for: liveType) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                loginStatusBadge(syncService.isLoggedIn(pluginId: entry.pluginId))
            }
        }
        .buttonStyle(.plain)
    }

    private var selectedPlatformBinding: Binding<LoginPlatformEntry?> {
        Binding(
            get: {
                guard let id = selectedLoginPluginId else { return nil }
                return platforms.first { $0.pluginId == id }
            },
            set: { newValue in
                selectedLoginPluginId = newValue?.pluginId
            }
        )
    }

    private func loadPlatforms() async {
        let all = await PlatformLoginRegistry.shared.availablePlatforms()
        platforms = all.filter { pluginAvailability.isPluginInstalled(for: $0.pluginId) }
    }

    private func loginMethodDescription(for entry: LoginPlatformEntry) -> String {
        entry.loginChallenge?.isSupportedByCurrentHost == true ? "支持扫码或网页登录" : "网页登录 Cookie 同步"
    }

    private func loginStatusBadge(_ isLoggedIn: Bool) -> some View {
        PanelStatusBadge(isLoggedIn ? "已登录" : "未登录", tint: isLoggedIn ? AppConstants.Colors.success : .secondary)
    }
}
