import SwiftUI
import CoreImage.CIFilterBuiltins

/// FullUI-only presentation. The view receives challenge/status data, never tokens.
public struct PlatformDeviceLoginView: View {
    private let entry: LoginPlatformEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesMacSettingsPresentation) private var usesSettingsPresentation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var loginId = UUID().uuidString
    @State private var challenge: DeviceLoginChallenge?
    @State private var qrImage: CGImage?
    @State private var message = "正在生成设备码…"
    @State private var finished = false
    @State private var connected = false
    @State private var clearing = false
    @State private var clearError: String?
    @State private var account = PlatformAPITokenService.shared
    #if os(iOS)
    @State private var selectedDetent: PresentationDetent = .large
    #endif

    public init(entry: LoginPlatformEntry) { self.entry = entry }

    public var body: some View {
        NavigationStack {
            Group {
                if connected {
                    DeviceLoginSuccessContent(displayName: entry.displayName, clearing: clearing,
                        error: clearError, onDone: { dismiss() }, onDisconnect: clearAccount)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if !usesSettingsPresentation {
                                Text("登录 \(entry.displayName)").font(.title2.bold())
                            }
                            PlatformAPITokenStatusLabel(pluginId: entry.pluginId)
                            if let challenge, !finished {
                                if let qrImage {
                                    Image(decorative: qrImage, scale: 1)
                                        .interpolation(.none).resizable().scaledToFit()
                                        .frame(maxWidth: 280, maxHeight: 280)
                                        .padding(16).background(.white, in: RoundedRectangle(cornerRadius: 12))
                                        .accessibilityLabel("用手机扫描以打开授权页面")
                                }
                                Text(challenge.userCode).font(.title.monospaced().bold())
                                    .accessibilityLabel("设备码：\(challenge.userCode)")
                                Text("用手机扫描二维码，在授权页面输入设备码并确认。")
                                    .multilineTextAlignment(.center)
                                #if !os(tvOS)
                                Link("打开授权页面", destination: challenge.verificationUri)
                                #endif
                            }
                            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            if !finished { ProgressView() }
                            if finished && !connected {
                                Button("重新生成") {
                                    challenge = nil
                                    qrImage = nil
                                    finished = false
                                    loginId = UUID().uuidString
                                }.buttonStyle(.borderedProminent)
                            }
                            if account.statuses[entry.pluginId] != nil {
                                Button("退出 API 登录", role: .destructive, action: clearAccount)
                                    .disabled(clearing)
                            }
                            if !usesSettingsPresentation {
                                Button(connected ? "完成" : "关闭") { dismiss() }
                            }
                        }
                        .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                    }
                }
            }
            .macSettingsPage("\(entry.displayName) 登录", closeTitle: connected ? "完成" : "关闭", closeDisabled: clearing)
        }
        #if os(iOS)
        .presentationDetents(connected && !dynamicTypeSize.isAccessibilitySize ? [.height(400), .large] : [.large], selection: $selectedDetent)
        .presentationDragIndicator(connected ? .visible : .automatic)
        .onChange(of: connected && !dynamicTypeSize.isAccessibilitySize) { _, compact in
            selectedDetent = compact ? .height(400) : .large
        }
        #endif
        #if os(macOS)
        .frame(minWidth: 480, minHeight: connected ? 400 : 600)
        #endif
        .task(id: loginId) { await run(loginId) }
        .onDisappear {
            let id = loginId
            challenge = nil
            qrImage = nil
            Task { await LiveParsePlugins.shared.deviceAuth.cancel(pluginId: entry.pluginId, loginId: id, manager: LiveParsePlugins.shared) }
        }
    }

    @MainActor private func clearAccount() {
        clearing = true
        clearError = nil
        Task {
            defer { clearing = false }
            do {
                try await account.clear(pluginId: entry.pluginId)
                challenge = nil
                qrImage = nil
                finished = true
                connected = false
                message = "已退出 API 登录"
            } catch {
                clearError = "退出失败，请稍后重试。"
                message = "退出失败，请稍后重试。"
            }
        }
    }

    @MainActor private func run(_ id: String) async {
        let manager = LiveParsePlugins.shared
        do {
            let created = try await manager.deviceAuth.start(pluginId: entry.pluginId, loginId: id, manager: manager)
            try Task.checkCancellation()
            guard loginId == id else { return }
            challenge = created
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(created.verificationUri.absoluteString.utf8)
            filter.correctionLevel = "M"
            guard let output = filter.outputImage,
                  let image = CIContext().createCGImage(output, from: output.extent) else { throw APITokenError.invalid }
            qrImage = image
            message = "等待你在授权页面确认…"
            var delay = created.retryAfter
            while !Task.isCancelled {
                if Date().timeIntervalSince1970 >= created.expiresAt {
                    message = "设备码已过期，请重新生成。"
                    finished = true
                    break
                }
                try await Task.sleep(for: .seconds(min(delay, max(0, created.expiresAt - Date().timeIntervalSince1970))))
                if scenePhase != .active { delay = 1; continue }
                let progress = try await manager.deviceAuth.poll(pluginId: entry.pluginId, loginId: id, manager: manager)
                try Task.checkCancellation()
                if clearing || finished { break }
                switch progress {
                case .waiting(let retry): delay = retry
                case .confirmed:
                    connected = true
                    message = "API 已连接"
                    finished = true
                case .denied: message = "授权已取消"; finished = true
                case .expired: message = "设备码已过期，请重新生成。"; finished = true
                case .failed: message = "登录失败，请重新生成或稍后重试。"; finished = true
                }
                if finished { break }
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled && loginId == id {
                message = "登录未完成；原有账号已保留。请稍后重试。"
                finished = true
            }
        }
        await manager.deviceAuth.cancel(pluginId: entry.pluginId, loginId: id, manager: manager)
        if loginId == id { challenge = nil; qrImage = nil }
    }
}

private struct DeviceLoginSuccessContent: View {
    @Environment(\.usesMacSettingsPresentation) private var usesSettingsPresentation
    let displayName: String
    let clearing: Bool
    let error: String?
    let onDone: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("登录成功").font(.title2.bold())
                        Text("\(displayName) 已连接")
                            .font(.body).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                VStack(spacing: 12) {
                    if !usesSettingsPresentation {
                        Button(action: onDone) {
                            Text("完成").fontWeight(.semibold)
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(clearing)
                    }
                    Menu {
                        Button("退出登录", role: .destructive, action: onDisconnect)
                    } label: {
                        Label("账号选项", systemImage: "ellipsis.circle")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                    .foregroundStyle(.secondary)
                    .disabled(clearing)
                    if clearing { ProgressView("正在退出…") }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 36)
            .frame(maxWidth: 440).frame(maxWidth: .infinity)
        }
    }
}

#Preview("设备登录成功") {
    DeviceLoginSuccessContent(displayName: "示例平台", clearing: false, error: nil,
        onDone: {}, onDisconnect: {})
        .frame(width: 390, height: 400)
}
