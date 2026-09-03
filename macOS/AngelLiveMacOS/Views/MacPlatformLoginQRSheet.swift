//
//  MacPlatformLoginQRSheet.swift
//  AngelLiveMacOS
//
//  插件驱动的二维码登录入口。二维码图片由 macOS 宿主原生生成。
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import AngelLiveCore

private enum MacPlatformLoginMethod {
    case qrCode
    case web
}

struct MacPlatformLoginSheet: View {
    let entry: LoginPlatformEntry

    @State private var method: MacPlatformLoginMethod

    init(entry: LoginPlatformEntry, isLoggedIn: Bool) {
        self.entry = entry
        let supportsQRCode = entry.loginChallenge?.isSupportedByCurrentHost == true
        let prefersQRCode = entry.loginChallenge?.prefers(.macOS) == true
        _method = State(initialValue: !isLoggedIn && supportsQRCode && prefersQRCode ? .qrCode : .web)
    }

    var body: some View {
        switch method {
        case .qrCode:
            MacPlatformLoginQRSheet(
                entry: entry,
                onUseWebLogin: { method = .web }
            )
        case .web:
            MacPlatformLoginWebSheet(
                pluginId: entry.pluginId,
                onUseQRCode: entry.loginChallenge?.isSupportedByCurrentHost == true
                    ? { method = .qrCode }
                    : nil
            )
        }
    }
}

private struct MacPlatformLoginQRSheet: View {
    let entry: LoginPlatformEntry
    let onUseWebLogin: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var service = PlatformLoginChallengeService()
    @State private var backgroundTimeoutTask: Task<Void, Never>?
    @State private var backgroundedAt: Date?
    @State private var verificationCode = ""
    @FocusState private var verificationFieldFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .navigationTitle("\(entry.displayName) 扫码登录")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("网页登录") { onUseWebLogin() }
                    }
                }
        }
        .task {
            service.start(entry: entry, platform: .macOS)
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .onChange(of: service.state) { _, newState in
            guard case .awaitingVerification = newState else {
                verificationCode = ""
                return
            }
        }
        .onDisappear {
            cancelBackgroundTimeout()
            verificationCode = ""
            service.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .idle, .creating:
            progressContent("正在创建二维码…")
        case .presenting(let presentation):
            challengeContent(presentation, scanned: false)
        case .scanned(let presentation):
            challengeContent(presentation, scanned: true)
        case .awaitingVerification(let presentation):
            verificationContent(presentation, isWorking: false)
        case .submittingVerification(let presentation):
            verificationContent(presentation, isWorking: true)
        case .requestingVerificationCode(let presentation):
            verificationContent(presentation, isWorking: true)
        case .validating:
            progressContent("正在验证登录信息…")
        case .succeeded(let success):
            successContent(success)
        case .failed(let failure):
            failureContent(failure)
        @unknown default:
            progressContent("正在准备扫码登录…")
        }
    }

    private func verificationContent(
        _ presentation: LoginChallengeVerificationPresentation,
        isWorking: Bool
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "message.badge.waveform.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("需要短信验证")
                .font(.title2.bold())
            Text(presentation.prompt)
            if let destination = presentation.maskedDestination {
                Text("验证码已发送至 \(destination)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            SecureField("短信验证码", text: $verificationCode)
                .textContentType(.oneTimeCode)
                .focused($verificationFieldFocused)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit { submitVerificationCode(presentation) }
                .onChange(of: verificationCode) { _, value in
                    verificationCode = String(value.prefix(presentation.codeLength))
                }
            if let errorMessage = presentation.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(errorMessage == "验证码已重新发送" ? Color.secondary : Color.red)
            }
            Button(isWorking ? "正在验证…" : "验证并继续") {
                submitVerificationCode(presentation)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count != presentation.codeLength)
            resendButton(presentation, isWorking: isWorking)
            Button("改用网页登录") { onUseWebLogin() }
        }
        .onAppear { verificationFieldFocused = !isWorking }
    }

    @ViewBuilder
    private func resendButton(
        _ presentation: LoginChallengeVerificationPresentation,
        isWorking: Bool
    ) -> some View {
        if presentation.canResend {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(presentation.resendAvailableAt?.timeIntervalSince(context.date) ?? 0)))
                Button(remaining > 0 ? "\(remaining) 秒后可重新发送" : "重新发送验证码") {
                    service.resendVerificationCode()
                }
                .disabled(isWorking || remaining > 0)
            }
        }
    }

    private func submitVerificationCode(_ presentation: LoginChallengeVerificationPresentation) {
        let code = verificationCode
        guard code.trimmingCharacters(in: .whitespacesAndNewlines).count == presentation.codeLength else { return }
        verificationCode = ""
        service.submitVerificationCode(code)
    }

    private func challengeContent(_ presentation: LoginChallengePresentation, scanned: Bool) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: qrCodeImage(presentation))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("\(entry.displayName) 登录二维码")

                Label(
                    scanned ? "已扫码，请在手机上确认" : "等待扫码",
                    systemImage: scanned ? "iphone.radiowaves.left.and.right" : "qrcode.viewfinder"
                )
                .font(.headline)

                Text(presentation.hint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                Button("改用网页登录") {
                    onUseWebLogin()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func progressContent(_ message: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(message)
                .font(.headline)
            Text("请保持此窗口打开")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func successContent(_ success: LoginChallengeSuccess) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("登录成功")
                .font(.title2.bold())
            if let userName = success.userName, !userName.isEmpty {
                Text(userName)
                    .foregroundStyle(.secondary)
            }
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func failureContent(_ failure: LoginChallengeFailure) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)
                Text("扫码登录失败")
                    .font(.title2.bold())
                Text(failure.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)

                HStack(spacing: 12) {
                    if failure.canRetry {
                        Button("重试") { service.retry() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("改用网页登录") { onUseWebLogin() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            let exceededTimeout = backgroundedAt.map {
                Date().timeIntervalSince($0) >= 60
            } ?? false
            cancelBackgroundTimeout()
            if exceededTimeout {
                cancelChallengeAndDismiss()
            }
        case .background:
            guard backgroundTimeoutTask == nil else { return }
            backgroundedAt = Date()
            backgroundTimeoutTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                cancelChallengeAndDismiss()
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func cancelBackgroundTimeout() {
        backgroundTimeoutTask?.cancel()
        backgroundTimeoutTask = nil
        backgroundedAt = nil
    }

    private func cancelChallengeAndDismiss() {
        cancelBackgroundTimeout()
        service.cancel()
        dismiss()
    }

    private func qrCodeImage(_ presentation: LoginChallengePresentation) -> NSImage {
        if let data = presentation.qrImageData, let image = NSImage(data: data) {
            return image
        }
        return MacLoginQRCodeGenerator.generate(from: presentation.qrContent)
    }
}

private enum MacLoginQRCodeGenerator {
    static func generate(from string: String) -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let context = CIContext()

        if let outputImage = filter.outputImage?.transformed(by: transform),
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            )
        }

        return NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "二维码生成失败") ?? NSImage()
    }
}
