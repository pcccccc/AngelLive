//
//  PlatformLoginQRCodeSheet.swift
//  AngelLive
//
//  插件驱动的二维码登录入口。优先展示插件提供的 PNG，否则由宿主编码 qrContent。
//

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import AngelLiveCore

private enum PlatformLoginMethod {
    case qrCode
    case web
}

struct PlatformLoginSheet: View {
    let entry: LoginPlatformEntry

    @State private var method: PlatformLoginMethod

    init(entry: LoginPlatformEntry, isLoggedIn: Bool) {
        self.entry = entry

        let supportsQRCode = entry.loginChallenge?.isSupportedByCurrentHost == true
        let prefersQRCode = entry.loginChallenge?.prefers(.iOS) == true
        // iPhone 上默认展示自身二维码并不实用，仍以网页登录为首选；iPad 才遵循 preferOn。
        let canPreferQRCodeHere = UIDevice.current.userInterfaceIdiom != .phone
        _method = State(initialValue: !isLoggedIn && supportsQRCode && prefersQRCode && canPreferQRCodeHere ? .qrCode : .web)
    }

    var body: some View {
        switch method {
        case .qrCode:
            PlatformLoginQRCodeSheet(
                entry: entry,
                onUseWebLogin: { method = .web }
            )
        case .web:
            PlatformLoginWebSheet(
                pluginId: entry.pluginId,
                onUseQRCode: entry.loginChallenge?.isSupportedByCurrentHost == true
                    ? { method = .qrCode }
                    : nil
            )
        }
    }
}

private struct PlatformLoginQRCodeSheet: View {
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
                .padding(24)
                .navigationTitle("\(entry.displayName) 扫码登录")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("网页登录") { onUseWebLogin() }
                    }
                }
        }
        .task {
            service.start(entry: entry, platform: .iOS)
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
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "message.badge.waveform.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("需要短信验证")
                    .font(.title2.bold())
                Text(presentation.prompt)
                    .multilineTextAlignment(.center)
                if let destination = presentation.maskedDestination {
                    Text("验证码已发送至 \(destination)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SecureField("短信验证码", text: $verificationCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($verificationFieldFocused)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .submitLabel(.done)
                    .onSubmit { submitVerificationCode(presentation) }
                    .onChange(of: verificationCode) { _, value in
                        verificationCode = String(value.prefix(presentation.codeLength))
                    }

                if let errorMessage = presentation.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(errorMessage == "验证码已重新发送" ? Color.secondary : Color.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    submitVerificationCode(presentation)
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("验证并继续")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || verificationCode.trimmingCharacters(in: .whitespacesAndNewlines).count != presentation.codeLength)

                resendButton(presentation, isWorking: isWorking)
                Button("改用网页登录") { onUseWebLogin() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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
            VStack(spacing: 20) {
                Image(uiImage: qrCodeImage(presentation))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func progressContent(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(.headline)
            Text("请保持此页面打开")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func successContent(_ success: LoginChallengeSuccess) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
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
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
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
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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

    private func qrCodeImage(_ presentation: LoginChallengePresentation) -> UIImage {
        if let data = presentation.qrImageData, let image = UIImage(data: data) {
            return image
        }
        return PlatformLoginQRCodeGenerator.generate(from: presentation.qrContent)
    }
}

private enum PlatformLoginQRCodeGenerator {
    static func generate(from string: String) -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        let output = filter.outputImage?.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        )
        let context = CIContext()
        guard let output,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}
