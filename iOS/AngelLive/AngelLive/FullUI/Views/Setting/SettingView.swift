//
//  SettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveCore
import Kingfisher

struct SettingView: View {
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @State private var generalSetting = GeneralSettingModel()
    @State private var cacheSizeText: String = "计算中..."
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false
    @State private var supportDiagnosticsService = SupportDiagnosticsService.shared
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.supportDiagnosticsEnabled) private var supportDiagnosticsEnabled

    var body: some View {
        @Bindable var setting = generalSetting
        NavigationStack {
            List {
                // 账号设置
                if pluginAvailability.hasAvailablePlugins,
                   !pluginAvailability.loginRequiredInstalledPluginIds.isEmpty {
                    Section {
                        NavigationLink {
                            PlatformAccountLoginView()
                                .fullUITabBarHidden()
                                .onAppear {
                                    guard supportDiagnosticsEnabled else { return }
                                    supportDiagnosticsService.recordAction(.openedAccountManagement)
                                }
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .font(.title3)
                                    .foregroundStyle(AppConstants.Colors.link.gradient)
                                .frame(width: 24, height: 24)
                                .frame(width: 32)

                                Text("平台账号登录")

                                Spacer()

                                Text("多平台")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                        }
                    } header: {
                        Text("账号")
                    }
                }

                // 插件管理
                if pluginAvailability.hasAvailablePlugins {
                    Section {
                        NavigationLink {
                            PluginManagementView()
                                .fullUITabBarHidden()
                                .onAppear {
                                    guard supportDiagnosticsEnabled else { return }
                                    supportDiagnosticsService.recordAction(.openedPluginManagement)
                                }
                        } label: {
                            HStack {
                                Image(systemName: "puzzlepiece.extension.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.orange.gradient)
                                    .frame(width: 32)

                                Text("插件管理")

                                Spacer()

                                Text("\(pluginAvailability.installedPluginIds.count) 个已安装")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                        }
                    } header: {
                        Text("插件")
                    }
                }

                // 应用设置
                Section {
                    NavigationLink {
                        GeneralSettingView()
                            .fullUITabBarHidden()
                    } label: {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .font(.title3)
                                .foregroundStyle(Color.gray.gradient)
                                .frame(width: 32)
                            Text("通用设置")
                        }
                    }

                    NavigationLink {
                        DanmuSettingView()
                            .fullUITabBarHidden()
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.success.gradient)
                                .frame(width: 32)
                            Text("弹幕设置")
                        }
                    }

                    NavigationLink {
                        TranslationSettingView()
                            .fullUITabBarHidden()
                    } label: {
                        HStack {
                            Image(systemName: "character.book.closed.fill")
                                .font(.title3)
                                .foregroundStyle(Color.indigo.gradient)
                                .frame(width: 32)
                            Text("翻译与字幕")
                        }
                    }
                } header: {
                    Text("设置")
                }

                // 数据同步（有插件时可用）
                if pluginAvailability.hasAvailablePlugins {
                    Section {
                        NavigationLink {
                            SyncView()
                                .fullUITabBarHidden()
                        } label: {
                            HStack {
                                Image(systemName: "icloud.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.cyan.gradient)
                                    .frame(width: 32)

                                Text("数据同步")
                            }
                        }
                    } header: {
                        Text("同步")
                    } footer: {
                        Text("使用 iCloud 同步收藏和平台账号，也可将已登录的平台账号同步到 Apple TV。")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                }

                // 历史记录（始终可用）
                Section {
                    NavigationLink {
                        HistoryListView()
                            .fullUITabBarHidden()
                    } label: {
                        HStack {
                            Image(systemName: "clock.fill")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.warning.gradient)
                                .frame(width: 32)
                            Text("历史记录")
                        }
                    }
                } header: {
                    Text("记录")
                }

                // 开发者
                Section {
                    HStack {
                        Image(systemName: "hammer.fill")
                            .font(.title3)
                            .foregroundStyle(Color.red.gradient)
                            .frame(width: 32)

                        Toggle("开发者模式", isOn: $setting.developerModeEnabled)
                    }
                } header: {
                    Text("开发者")
                } footer: {
                    Text("开启后显示浮动调试按钮，可查看插件运行日志。")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                // 存储
                Section {
                    Button {
                        showClearCacheConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                                .font(.title3)
                                .foregroundStyle(Color.red.gradient)
                                .frame(width: 32)

                            Text("清除缓存")
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Spacer()

                            if isClearingCache {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("清理中...")
                                        .font(.subheadline)
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }
                            } else {
                                Text(cacheSizeText)
                                    .font(.subheadline)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)
                            }
                        }
                    }
                    .disabled(isClearingCache)
                } header: {
                    Text("存储")
                } footer: {
                    Text("清理图片缓存、插件旧版本及网络临时文件。保留收藏、登录与已激活的插件版本。")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                // 帮助（仅 FullUI 根入口显式启用）
                if supportDiagnosticsEnabled {
                    Section {
                        NavigationLink {
                            SupportDiagnosticsView()
                                .fullUITabBarHidden()
                        } label: {
                            HStack {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.title3)
                                    .foregroundStyle(Color.orange.gradient)
                                    .frame(width: 32)

                                Text("问题诊断与反馈")

                                Spacer()

                                if supportDiagnosticsService.isRecording {
                                    Label("录制中", systemImage: "record.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .labelStyle(.titleAndIcon)
                                }
                            }
                        }
                    } header: {
                        Text("帮助")
                    }
                }

                // 关于
                Section {
                    NavigationLink {
                        OpenSourceListView()
                            .fullUITabBarHidden()
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .font(.title3)
                                .foregroundStyle(Color.purple.gradient)
                                .frame(width: 32)
                            Text("开源许可")
                        }
                    }

                    NavigationLink {
                        AboutUSView()
                            .fullUITabBarHidden()
                    } label: {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.indigo.gradient)
                                .frame(width: 32)
                            Text("关于")
                        }
                    }
                } header: {
                    Text("信息")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await refreshCacheSize()
            }
            .alert(
                "确认清除所有缓存?",
                isPresented: $showClearCacheConfirm
            ) {
                Button("取消", role: .cancel) {}
                Button("清除", role: .destructive) {
                    Task { await clearAllCaches() }
                }
            } message: {
                Text("将清理图片缓存、插件旧版本及网络临时文件,不影响收藏与登录状态。")
            }
        }
    }

    private func refreshCacheSize() async {
        let total = await CacheMaintenanceService.currentTotalSize(imageCache: Self.kingfisherBridge)
        await MainActor.run {
            guard !isClearingCache else { return }
            cacheSizeText = CacheMaintenanceService.formatBytes(total)
        }
    }

    private func clearAllCaches() async {
        await MainActor.run { isClearingCache = true }
        let total = await CacheMaintenanceService.purgeAllAndAwaitSettled(
            imageCache: Self.kingfisherBridge
        )
        await MainActor.run {
            cacheSizeText = CacheMaintenanceService.formatBytes(total)
            isClearingCache = false
        }
    }

    private static let kingfisherBridge = CacheMaintenanceService.ImageCacheBridge(
        measureBytes: {
            await withCheckedContinuation { (cont: CheckedContinuation<Int64, Never>) in
                ImageCache.default.calculateDiskStorageSize { result in
                    cont.resume(returning: (try? result.get()).map(Int64.init) ?? 0)
                }
            }
        },
        clearDisk: {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                ImageCache.default.clearDiskCache { cont.resume() }
            }
        },
        clearMemory: {
            ImageCache.default.clearMemoryCache()
        }
    )
}

// MARK: - Room title translation

struct TranslationSettingView: View {
    private struct TargetLanguage: Identifiable {
        let code: String
        let name: String

        var id: String { code }
    }

    private let targetLanguages = [
        TargetLanguage(code: "zh-Hans", name: "中文简体"),
        TargetLanguage(code: "zh-Hant", name: "中文繁体"),
        TargetLanguage(code: "en", name: "英语"),
        TargetLanguage(code: "ja", name: "日语"),
        TargetLanguage(code: "ko", name: "韩语")
    ]

    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = RoomTranslationSettings.shared
    @State private var translationService = RoomTitleTranslationService.shared
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var isTesting = false
    @State private var isDeletingKey = false
    @State private var inlineMessage: String?
    @State private var testResult: String?
    @State private var activeTask: Task<Void, Never>?
    @State private var testGeneration = UUID()

    private var configurationNeedsSave: Bool {
        let normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedBaseURL != settings.cloudBaseURL
            || normalizedModel != settings.cloudModel
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTest: Bool {
        guard !isSaving, !isTesting, !isDeletingKey else { return false }
        guard settings.engine == .apple else {
            return !configurationNeedsSave
                && settings.hasAPIKey
                && !settings.cloudBaseURL.isEmpty
                && !settings.cloudModel.isEmpty
        }
        return true
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Toggle(isOn: $settings.isEnabled) {
                    TranslationSettingLabel(
                        title: "自动翻译房间标题",
                        systemImage: "character.book.closed.fill",
                        tint: .indigo
                    )
                }
                .tint(AppConstants.Colors.accent)

                Toggle(isOn: $settings.isDanmakuEnabled) {
                    TranslationSettingLabel(
                        title: "自动翻译弹幕",
                        systemImage: "text.bubble.fill",
                        tint: .green
                    )
                }
                .tint(AppConstants.Colors.accent)

                Picker(selection: $settings.targetLanguage) {
                    ForEach(targetLanguages) { language in
                        Text(language.name)
                            .tag(language.code)
                    }
                } label: {
                    TranslationSettingLabel(
                        title: "目标语言",
                        systemImage: "globe",
                        tint: .blue
                    )
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("自动翻译")
            } footer: {
                Text("翻译成功显示译文，失败或来不及翻译保留原文；图文弹幕保留图片表情。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }

            Section {
                Picker(selection: $settings.engine) {
                    ForEach(RoomTranslationEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName)
                            .tag(engine)
                    }
                } label: {
                    TranslationSettingLabel(
                        title: "翻译引擎",
                        systemImage: "cpu",
                        tint: .purple
                    )
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("引擎")
            } footer: {
                Text("Apple 原生翻译需要 iOS 18 或更高版本。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }

            if settings.engine == .llm {
                Section {
                    TextField("https://api.example.invalid/v1", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel("服务地址")

                    TextField("模型名称", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("模型")

                    SecureField(settings.hasAPIKey ? "留空保持已保存密钥" : "API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("API Key")

                    Button {
                        saveConfiguration()
                    } label: {
                        HStack {
                            Text("保存配置")
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isSaving || isTesting || isDeletingKey)

                    if settings.hasAPIKey {
                        Button("删除已保存密钥", role: .destructive) {
                            deleteAPIKey()
                        }
                        .disabled(isSaving || isTesting || isDeletingKey)
                    }
                } header: {
                    Text("兼容 AI 接口")
                } footer: {
                    Text("开启对应开关后，房间标题或弹幕文本会发送至你配置的服务。弹幕频率较高，可能增加用量或费用；不会发送用户名或图片 URL。API Key 只保存在本机安全存储中。")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
            }

            Section {
                Button {
                    testTranslation()
                } label: {
                    HStack {
                        Text("测试翻译")
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(!canTest)

                if configurationNeedsSave, settings.engine == .llm {
                    Text("请先保存接口配置，再测试翻译。")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }

                if let inlineMessage {
                    Text(inlineMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let serviceError = translationService.lastErrorMessage {
                    Text(serviceError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let testResult {
                    LabeledContent("结果") {
                        Text(testResult)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("连接测试")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("翻译与字幕")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            baseURL = settings.cloudBaseURL
            model = settings.cloudModel
        }
        .onChange(of: settings.engine) { _, _ in
            resetTranslationFeedback()
        }
        .onChange(of: settings.targetLanguage) { _, _ in
            resetTranslationFeedback()
        }
        .onDisappear {
            testGeneration = UUID()
            activeTask?.cancel()
            activeTask = nil
            isTesting = false
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, isTesting else { return }
            testGeneration = UUID()
            activeTask?.cancel()
            activeTask = nil
            isTesting = false
            inlineMessage = nil
            testResult = nil
            translationService.clearError()
        }
    }

    private func saveConfiguration() {
        testGeneration = UUID()
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            isSaving = true
            inlineMessage = nil
            testResult = nil
            defer { isSaving = false }

            do {
                try settings.saveCloudConfiguration(baseURL: baseURL, model: model, apiKey: apiKey)
                baseURL = settings.cloudBaseURL
                model = settings.cloudModel
                apiKey = ""
            } catch {
                guard !Task.isCancelled else { return }
                inlineMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func deleteAPIKey() {
        testGeneration = UUID()
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            isDeletingKey = true
            inlineMessage = nil
            testResult = nil
            defer { isDeletingKey = false }

            do {
                try settings.deleteAPIKey()
            } catch {
                guard !Task.isCancelled else { return }
                inlineMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func testTranslation() {
        let generation = UUID()
        testGeneration = generation
        activeTask?.cancel()
        activeTask = Task { @MainActor in
            guard !Task.isCancelled, testGeneration == generation else { return }
            isTesting = true
            inlineMessage = nil
            testResult = nil
            translationService.clearError()
            defer {
                if testGeneration == generation {
                    isTesting = false
                    activeTask = nil
                }
            }

            do {
                let result = try await translationService.testTranslation()
                guard !Task.isCancelled, testGeneration == generation else { return }
                testResult = result
            } catch {
                guard !Task.isCancelled, testGeneration == generation else { return }
                inlineMessage = translationService.lastErrorMessage
                    ?? (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func resetTranslationFeedback() {
        testGeneration = UUID()
        activeTask?.cancel()
        isTesting = false
        inlineMessage = nil
        testResult = nil
        translationService.clearError()
    }
}

private struct TranslationSettingLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint.gradient)
                .frame(width: 30, height: 30)

            Text(title)
        }
    }
}

// MARK: - CloudKit Status View

struct CloudKitStatusView: View {
    let stateString: String

    var body: some View {
        VStack(spacing: AppConstants.Spacing.xl) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 60))
                .foregroundStyle(AppConstants.Colors.warning)

            Text("iCloud 状态异常")
                .font(.title2.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)

            Text(stateString)
                .font(.body)
                .foregroundStyle(AppConstants.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .navigationTitle("同步")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingView()
}
