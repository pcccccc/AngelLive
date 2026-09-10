import SwiftUI

/// Only presented by the platform hosts' FullUI account settings.
public struct PlatformAPITokenView: View {
    private let entry: LoginPlatformEntry
    private let kind: PlatformAPICredentialKind
    @Environment(\.dismiss) private var dismiss
    @State private var service = PlatformAPITokenService.shared
    @State private var token = ""
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var operation: Task<Void, Never>?
    @State private var isWorking = false
    @State private var errorMessage: String?

    public init(entry: LoginPlatformEntry, kind: PlatformAPICredentialKind = .token) {
        self.entry = entry
        self.kind = kind
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label(service.statusText(pluginId: entry.pluginId), systemImage: "key.fill")
                        .font(.headline)
                    if let status = service.statuses[entry.pluginId] {
                        LabeledContent("当前配置", value: status.credentialKind == "client_credentials" ? "Client ID 与 Client Secret" : "Access Token")
                        if let clientId = status.clientId, !clientId.isEmpty {
                            LabeledContent("Client ID", value: clientId)
                        }
                        if let expiry = status.expireAt, expiry > 0 {
                            LabeledContent("到期时间") {
                                Text(Date(timeIntervalSince1970: expiry), format: .dateTime)
                            }
                        } else { Text("到期时间未知").foregroundStyle(.secondary) }
                        if let type = status.tokenType { LabeledContent("Token 类型", value: type) }
                    }
                    Text(kind == .clientCredentials
                         ? "填写应用的 Client ID 和 Client Secret，插件将自动获取并更新 API 授权。此配置不代表个人账号登录。"
                         : "API 凭据用于插件浏览授权，不代表个人账号登录。请在其他设备或浏览器中获取 Access Token，再粘贴到这里。")
                        .foregroundStyle(.secondary)
                    if kind == .clientCredentials {
                        credentialInput("Client ID", text: $clientId)
                        credentialInput("Client Secret", text: $clientSecret)
                        Text("应用凭据仅保存在本机安全存储中，自动续期由插件处理。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        credentialInput("Access Token", text: $token)
                        Text("支持纯 Token、Bearer 或 OAuth 前缀。此方式需要手动更换过期 Token。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = errorMessage ?? service.failures[entry.pluginId] {
                        Text(error).foregroundStyle(.red)
                    }
                    if isWorking { ProgressView("正在校验…") }
                    Button(saveButtonTitle) { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || isInputEmpty)
                    if service.statuses[entry.pluginId] != nil {
                        Button("清除当前 API 配置", role: .destructive) { clear() }
                            .disabled(isWorking)
                    }
                    Button("关闭") { dismiss() }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("\(entry.displayName) API 凭据")
        }
        .task { await service.load(pluginId: entry.pluginId) }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 440)
        #endif
        .onDisappear {
            resetInput()
            operation?.cancel()
        }
    }

    private func credentialInput(_ title: String, text: Binding<String>) -> some View {
        Group {
            #if os(iOS)
            TextField(title, text: text)
            #else
            SecureField(title, text: text)
            #endif
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .autocorrectionDisabled()
        #if !os(macOS)
        .textInputAutocapitalization(.never)
        #endif
    }

    private var isInputEmpty: Bool {
        let values = kind == .clientCredentials ? [clientId, clientSecret] : [token]
        return values.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var saveButtonTitle: String {
        guard let status = service.statuses[entry.pluginId] else { return "校验并保存" }
        return status.credentialKind == kind.rawValue ? "校验并替换" : "校验并切换"
    }

    private func resetInput() { token = ""; clientId = ""; clientSecret = "" }

    private func save() {
        let candidate = token
        let candidateId = clientId
        let candidateSecret = clientSecret
        resetInput()
        isWorking = true
        errorMessage = nil
        operation = Task {
            defer { isWorking = false }
            do {
                if kind == .clientCredentials {
                    try await service.validateAndSave(pluginId: entry.pluginId, clientId: candidateId, clientSecret: candidateSecret)
                } else {
                    try await service.validateAndSave(pluginId: entry.pluginId, token: candidate)
                }
            }
            catch is CancellationError { }
            catch { errorMessage = "校验失败；原有凭据已保留。请检查输入或稍后重试。" }
        }
    }

    private func clear() {
        resetInput()
        isWorking = true
        errorMessage = nil
        operation = Task {
            defer { isWorking = false }
            do { try await service.clear(pluginId: entry.pluginId) }
            catch { errorMessage = "清除失败，请稍后重试。" }
        }
    }
}

public struct PlatformAPITokenStatusLabel: View {
    let pluginId: String
    @State private var service = PlatformAPITokenService.shared
    public init(pluginId: String) { self.pluginId = pluginId }
    public var body: some View {
        Text(service.statusText(pluginId: pluginId))
            .foregroundStyle(.secondary)
            .task { await service.load(pluginId: pluginId) }
    }
}

private struct PlatformAPICredentialLifecycle: ViewModifier {
    let enabled: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // The root catalog service owns policy activation. Keep the view
            // tree mounted while foreground credential validation runs.
            .task(id: enabled && scenePhase == .active) {
                guard enabled, scenePhase == .active else { return }
                do {
                    while !Task.isCancelled {
                        let entries = await PlatformLoginRegistry.shared.availablePlatforms()
                        for entry in entries where entry.supportsAPICredentials {
                            try Task.checkCancellation()
                            await PlatformAPITokenService.shared.load(pluginId: entry.pluginId)
                            await PlatformAPITokenService.shared.refresh(pluginId: entry.pluginId)
                        }
                        try await Task.sleep(for: .seconds(3_600))
                    }
                } catch { }
            }
    }
}

public extension View {
    /// Background status maintenance. The host's root PluginAvailabilityService
    /// must opt in to managesAPICredentialPolicy before creating browsing views.
    func platformAPICredentialLifecycle(enabled: Bool) -> some View {
        modifier(PlatformAPICredentialLifecycle(enabled: enabled))
    }
}

private struct APICredentialContentIdentity: ViewModifier {
    let pluginId: String?
    @State private var service = PlatformAPITokenService.shared
    func body(content: Content) -> some View {
        content.id(pluginId.map { service.revisions[$0, default: 0] } ?? service.contentRevision)
    }
}

public extension View {
    /// Apply outside a FullUI browsing view that owns its model, so replacement
    /// cancels view tasks and discards category/page/search state together.
    func apiCredentialContentIdentity(pluginId: String? = nil) -> some View {
        modifier(APICredentialContentIdentity(pluginId: pluginId))
    }
}
