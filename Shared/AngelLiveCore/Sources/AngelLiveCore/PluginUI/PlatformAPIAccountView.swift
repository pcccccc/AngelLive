import SwiftUI

/// FullUI account management for credentials already stored by the host.
public struct PlatformAPIAccountView: View {
    public let entry: LoginPlatformEntry
    public let onChangeLogin: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesMacSettingsPresentation) private var usesSettingsPresentation
    @State private var service = PlatformAPITokenService.shared
    @State private var working = false
    @State private var validationCompleted = false
    @State private var showLogout = false
    @State private var errorMessage: String?

    public init(entry: LoginPlatformEntry, onChangeLogin: @escaping () -> Void) {
        self.entry = entry
        self.onChangeLogin = onChangeLogin
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("账号信息") {
                    LabeledContent("平台", value: entry.displayName)
                    LabeledContent("状态", value: service.statusText(pluginId: entry.pluginId))
                    if let status = service.statuses[entry.pluginId] {
                        if let name = status.userName, !name.isEmpty {
                            LabeledContent("昵称", value: name)
                        }
                        if let expiry = status.expireAt, expiry > 0 {
                            LabeledContent("有效期至", value: Date(timeIntervalSince1970: expiry).formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                Section {
                    Button {
                        working = true
                        validationCompleted = false
                        errorMessage = nil
                        Task {
                            await service.refresh(pluginId: entry.pluginId)
                            errorMessage = service.failures[entry.pluginId]
                            validationCompleted = true
                            working = false
                        }
                    } label: {
                        HStack {
                            Text("重新校验凭证")
                            Spacer()
                            if working { ProgressView() }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if validationCompleted {
                        Text("校验完成：\(service.statusText(pluginId: entry.pluginId))")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("验证当前保存的登录凭据，并在需要时更新授权。")
                }
                Section {
                    Button("更换登录方式", action: onChangeLogin)
                    Button("退出登录", role: .destructive) { showLogout = true }
                }
            }
            .disabled(working)
            .navigationTitle("\(entry.displayName) 账号")
            .macSettingsPage("\(entry.displayName) 账号", closeTitle: "完成", closeDisabled: working)
            .toolbar {
                if !usesSettingsPresentation {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }.disabled(working)
                    }
                }
            }
            .task { await service.load(pluginId: entry.pluginId) }
            .alert("退出登录？", isPresented: $showLogout) {
                Button("取消", role: .cancel) {}
                Button("退出登录", role: .destructive) {
                    working = true
                    Task {
                        do {
                            try await service.clear(pluginId: entry.pluginId)
                            dismiss()
                        } catch {
                            errorMessage = "退出失败，请稍后重试。"
                        }
                        working = false
                    }
                }
            } message: {
                Text("将移除此平台在本机保存的 API 登录凭据。")
            }
        }
        .interactiveDismissDisabled(working)
    }
}
