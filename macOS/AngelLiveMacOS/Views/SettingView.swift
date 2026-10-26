//
//  SettingView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import Kingfisher

struct SettingView: View {
    #if !APPSTORE
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    #endif
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @AppStorage(MacDockIconPreference.storageKey)
    private var dockIconPreference = MacDockIconPreference.xiaoShengBiBi
    @AppStorage(MacPlaybackPresentationPreference.singlePageModeKey)
    private var singlePagePlayback = false

    @State private var playerSettingModel = PlayerSettingModel()
    @State private var showOpenSourceList = false
    @State private var showPluginManagement = false
    @State private var showDanmuSetting = false
    @State private var showAccountManagement = false
    @State private var showSyncManagement = false
    @State private var showTranslationSetting = false
    @State private var showSupportDiagnostics = false
    @State private var cacheSizeText: String = "计算中..."
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false
    @State private var supportDiagnosticsService = SupportDiagnosticsService.shared
    @Environment(\.supportDiagnosticsEnabled) private var supportDiagnosticsEnabled

    var body: some View {
        Form {
            if pluginAvailability.hasAvailablePlugins,
               !pluginAvailability.loginRequiredInstalledPluginIds.isEmpty {
                Section("账号") {
                    accountManagementRow
                }
            }

            if pluginAvailability.hasAvailablePlugins {
                Section {
                    syncManagementRow
                } header: {
                    Text("同步")
                } footer: {
                    Text("使用 iCloud 同步收藏与平台账号登录信息。")
                }
            }

            if pluginAvailability.hasAvailablePlugins {
                Section("插件与扩展") {
                    pluginManagementRow
                }
            }

            Section("通用设置") {
                appIconRow
                if pluginAvailability.hasAvailablePlugins {
                    translationSettingRow
                }
            }

            Section("播放") {
                if pluginAvailability.hasAvailablePlugins {
                    singlePagePlaybackRow
                    defaultPlaybackQualityRow
                }
                danmuSettingRow
            }

            Section("存储") {
                clearCacheRow
            }

            Section("关于与支持") {
                #if !APPSTORE
                checkUpdateRow
                #endif
                if supportDiagnosticsEnabled {
                    supportDiagnosticsRow
                }
                openSourceRow
                githubRow
            }

            Section {
                Text("AngelLive · macOS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .sheet(isPresented: $showAccountManagement) {
            NavigationStack {
                MacAccountManagementView()
                    .onAppear {
                        guard supportDiagnosticsEnabled else { return }
                        supportDiagnosticsService.recordAction(.openedAccountManagement)
                    }
            }
            .macSettingsSheetPresentation()
            .frame(minWidth: 600, minHeight: 480)
        }
        .sheet(isPresented: $showSyncManagement) {
            NavigationStack {
                MacSyncManagementView()
            }
            .macSettingsSheetPresentation()
            .frame(minWidth: 600, minHeight: 520)
        }
        .sheet(isPresented: $showTranslationSetting) {
            NavigationStack {
                TranslationSettingView()
            }
            .macSettingsSheetPresentation()
            .labelStyle(MacTranslationSettingLabelStyle())
            .frame(minWidth: 600, minHeight: 480)
        }
        .sheet(isPresented: $showPluginManagement) {
            MacPluginManagementView()
                .onAppear {
                    guard supportDiagnosticsEnabled else { return }
                    supportDiagnosticsService.recordAction(.openedPluginManagement)
                }
                .frame(minWidth: 600, idealWidth: 680, minHeight: 520, idealHeight: 640)
        }
        .sheet(isPresented: $showOpenSourceList) {
            if pluginAvailability.hasAvailablePlugins {
                NavigationStack {
                    OpenSourceListView(usesSettingsLayout: true)
                }
                .macSettingsSheetPresentation()
                .frame(minWidth: 600, minHeight: 500)
            } else {
                NavigationStack {
                    OpenSourceListView(usesSettingsLayout: false)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    showOpenSourceList = false
                                }
                            }
                        }
                }
                .frame(minWidth: 600, minHeight: 500)
            }
        }
        .sheet(isPresented: $showDanmuSetting) {
            if pluginAvailability.hasAvailablePlugins {
                NavigationStack {
                    MacDanmuSettingView(usesSettingsLayout: true)
                }
                .macSettingsSheetPresentation()
                .frame(minWidth: 680, minHeight: 640)
            } else {
                NavigationStack {
                    MacDanmuSettingView(usesSettingsLayout: false)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    showDanmuSetting = false
                                }
                            }
                        }
                }
                .frame(minWidth: 680, minHeight: 640)
            }
        }
        .sheet(isPresented: $showSupportDiagnostics) {
            if pluginAvailability.hasAvailablePlugins {
                NavigationStack { SupportDiagnosticsView() }
                    .macSettingsSheetPresentation()
                    .frame(minWidth: 600, idealWidth: 640, minHeight: 520, idealHeight: 560)
            } else {
                NavigationStack {
                    SupportDiagnosticsView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("关闭", systemImage: "xmark") {
                                    showSupportDiagnostics = false
                                }
                                .labelStyle(.iconOnly)
                                .help("关闭问题诊断")
                                .keyboardShortcut(.cancelAction)
                            }
                        }
                }
                .frame(minWidth: 600, idealWidth: 640, minHeight: 520, idealHeight: 560)
            }
        }
        .task {
            await refreshCacheSize()
        }
        .onChange(of: pluginAvailability.hasAvailablePlugins) { _, hasPlugins in
            if !hasPlugins {
                showTranslationSetting = false
            }
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

    private var clearCacheRow: some View {
        Button {
            showClearCacheConfirm = true
        } label: {
            PanelNavigationRow(
                title: "清除缓存",
                subtitle: "清理图片缓存、插件旧版本及临时文件",
                showsChevron: false
            ) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.red.gradient)
            } trailing: {
                if isClearingCache {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("清理中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(cacheSizeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isClearingCache)
    }

    private var appIconRow: some View {
        PanelNavigationRow(
            title: "应用图标",
            subtitle: "选择应用运行期间显示的 Dock 图标",
            showsChevron: false
        ) {
            Image(nsImage: dockIconPreference.previewImage)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(.rect(cornerRadius: 7))
        } trailing: {
            Picker("应用图标", selection: $dockIconPreference) {
                ForEach(MacDockIconPreference.allCases) { choice in
                    Text(choice.title)
                        .tag(choice)
                }
            }
            .labelsHidden()
            .frame(
                minWidth: 160,
                alignment: pluginAvailability.hasAvailablePlugins ? .trailing : .center
            )
            .onChange(of: dockIconPreference) { _, preference in
                preference.apply()
            }
            .help("macOS 仅在应用运行期间更换 Dock 图标。")
        }
    }

    private var translationSettingRow: some View {
        Button {
            showTranslationSetting = true
        } label: {
            PanelNavigationRow(
                title: "翻译与字幕",
                subtitle: "翻译标题、弹幕和实时字幕"
            ) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.indigo.gradient)
            }
        }
        .buttonStyle(.plain)
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

    private var accountManagementRow: some View {
        Button {
            showAccountManagement = true
        } label: {
            PanelNavigationRow(
                title: "账号管理",
                subtitle: "登录、查看与切换平台账号"
            ) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue.gradient)
            }
        }
        .buttonStyle(.plain)
    }

    private var syncManagementRow: some View {
        Button {
            showSyncManagement = true
        } label: {
            PanelNavigationRow(
                title: "同步管理",
                subtitle: "iCloud 自动同步、手动上传/下载"
            ) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.cyan.gradient)
            }
        }
        .buttonStyle(.plain)
    }

    private var pluginManagementRow: some View {
        Button {
            showPluginManagement = true
        } label: {
            PanelNavigationRow(
                title: "插件管理",
                subtitle: "统一管理订阅源、安装状态和版本更新"
            ) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orange.gradient)
            } trailing: {
                PanelStatusBadge(pluginAvailability.hasAvailablePlugins ? "已启用" : "未启用", tint: .orange)
            }
        }
        .buttonStyle(.plain)
    }

    private var singlePagePlaybackRow: some View {
        PanelNavigationRow(
            title: "单页模式",
            subtitle: "在主窗口内播放，关闭后返回浏览页面。",
            showsChevron: false
        ) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.blue.gradient)
        } trailing: {
            Toggle("单页模式", isOn: $singlePagePlayback)
                .labelsHidden()
                .toggleStyle(.switch)
                .help("关闭时使用独立播放窗口；主窗口全屏时仍在原窗口播放。")
        }
    }

    private var defaultPlaybackQualityRow: some View {
        @Bindable var playerSettingModel = playerSettingModel

        return PanelNavigationRow(
            title: "默认画质",
            subtitle: "进入直播间时按可用画质尽量匹配；网络较慢可选省流。",
            showsChevron: false
        ) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.blue.gradient)
        } trailing: {
            Picker("默认画质", selection: $playerSettingModel.defaultPlaybackQuality) {
                ForEach(DefaultPlaybackQuality.allCases, id: \.self) { quality in
                    Text(quality.title)
                        .tag(quality)
                }
            }
            .labelsHidden()
            .frame(minWidth: 160, alignment: .trailing)
            .help("进入直播间时按可用画质尽量匹配；网络较慢可选省流。")
        }
    }

    private var danmuSettingRow: some View {
        Button {
            showDanmuSetting = true
        } label: {
            PanelNavigationRow(
                title: "弹幕设置",
                subtitle: "显示、字体、速度和区域"
            ) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppConstants.Colors.success.gradient)
            }
        }
        .buttonStyle(.plain)
    }

    #if !APPSTORE
    private var checkUpdateRow: some View {
        Button {
            updaterViewModel.checkForUpdates()
        } label: {
            PanelNavigationRow(
                title: "检查更新",
                subtitle: updaterViewModel.canCheckForUpdates ? "查看新版本与更新说明" : "当前无法发起更新检查"
            ) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor.gradient)
            } trailing: {
                if !updaterViewModel.canCheckForUpdates {
                    PanelStatusBadge("不可用")
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!updaterViewModel.canCheckForUpdates)
    }
    #endif

    private var openSourceRow: some View {
        Button {
            showOpenSourceList = true
        } label: {
            PanelNavigationRow(
                title: "开源许可",
                subtitle: "查看第三方依赖与授权信息"
            ) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue.gradient)
            }
        }
        .buttonStyle(.plain)
    }

    private var githubRow: some View {
        Link(destination: URL(string: "https://github.com/pcccccc/AngelLive")!) {
            PanelNavigationRow(
                title: "访问 GitHub",
                subtitle: "项目主页、问题反馈与更新记录",
                showsChevron: false
            ) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.purple.gradient)
            } trailing: {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var supportDiagnosticsRow: some View {
        Button {
            showSupportDiagnostics = true
        } label: {
            PanelNavigationRow(
                title: "问题诊断与反馈",
                subtitle: "记录复现过程并在分享前预览报告"
            ) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.orange.gradient)
            } trailing: {
                if supportDiagnosticsService.isRecording {
                    Label("录制中", systemImage: "record.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("问题诊断与反馈")
        .accessibilityHint("打开诊断录制和报告预览")
    }

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
    @State private var isPreparingNativeLanguage = false
    @State private var nativeLanguagePairID: String?
    @State private var nativeLanguageGeneration = UUID()
    @State private var nativeLanguageDownloadRequest: NativeTranslationLanguageDownloadRequest?

    private var configurationNeedsSave: Bool {
        let normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedBaseURL != settings.cloudBaseURL
            || normalizedModel != settings.cloudModel
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTest: Bool {
        guard !isSaving, !isTesting, !isDeletingKey, !isPreparingNativeLanguage else { return false }
        guard settings.engine == .llm else { return true }
        return !configurationNeedsSave
            && settings.hasAPIKey
            && !settings.cloudBaseURL.isEmpty
            && !settings.cloudModel.isEmpty
    }

    private var nativeLanguagePairs: [NativeTranslationLanguagePair] {
        translationService.nativeLanguagePairs
    }

    private var cloudServiceExplanation: String {
        "填写服务商提供的 API 地址（通常以 /v1 结尾），需支持 Chat Completions 接口。\n只发送待翻译文字，不上传音频；服务商可能收费。API Key 仅保存在本机。"
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle(isOn: $settings.isEnabled) {
                    MacTranslationSettingLabel(
                        title: "自动翻译房间标题", systemImage: "character.book.closed.fill"
                    )
                }

                Toggle(isOn: $settings.isDanmakuEnabled) {
                    MacTranslationSettingLabel(
                        title: "自动翻译弹幕", systemImage: "text.bubble.fill"
                    )
                }

                Picker("翻译成", selection: $settings.targetLanguage) {
                    ForEach(targetLanguages) { language in
                        Text(language.name)
                            .tag(language.code)
                    }
                }

            } header: {
                Text("自动翻译")
            } footer: {
                Text("自动识别标题和弹幕的语言，翻译不成功时显示原文。")
            }

            LiveSubtitleSettingsSection {
                MacTranslationSettingLabel(title: "实时字幕", systemImage: "waveform")
            } sourceLanguageLabel: {
                MacTranslationSettingLabel(title: "系统语音包", systemImage: "globe")
            } resourceLabel: {
                MacTranslationSettingLabel(title: "字幕识别文件", systemImage: "waveform")
            }

            Section {
                Picker("翻译方式", selection: $settings.engine) {
                    ForEach(RoomTranslationEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName)
                            .tag(engine)
                    }
                }

            } footer: {
                Text(settings.engine == .apple
                     ? settings.availabilityError?.localizedDescription ?? "使用系统翻译，需先下载下方语言包。"
                     : "填写下方配置，保存后点“测试翻译”。")
            }

            if settings.engine == .apple {
                Section {
                    ForEach(nativeLanguagePairs) { pair in
                        HStack {
                            MacTranslationSettingLabel(title: pair.displayName, systemImage: "globe")

                            Spacer()

                            if isPreparingNativeLanguage, nativeLanguagePairID == pair.id {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("请在系统弹窗中下载")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("请在系统弹窗中下载 \(pair.displayName)")
                            } else {
                                switch translationService.nativeLanguageStatus(for: pair) {
                                case .checking:
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("检查中")
                                            .foregroundStyle(.secondary)
                                    }
                                    .accessibilityElement(children: .combine)
                                case .notDownloaded:
                                    Button("下载") {
                                        prepareNativeLanguages(pair)
                                    }
                                    .accessibilityLabel("下载 \(pair.displayName)")
                                    .disabled(
                                        isSaving
                                            || isTesting
                                            || isDeletingKey
                                            || isPreparingNativeLanguage
                                    )
                                case .installed:
                                    Text("已下载")
                                        .foregroundStyle(.secondary)
                                case .unsupported:
                                    Text("当前系统不支持")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                } header: {
                    Text("翻译语言包")
                } footer: {
                    Text("点“下载”后，在系统弹窗中确认。")
                }
            }

            if settings.engine == .llm {
                Section {
                    LabeledContent("API 地址") {
                        TextField("", text: $baseURL, prompt: Text(verbatim: "https://api.example.invalid/v1"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .accessibilityLabel("API 地址")
                    }

                    LabeledContent("模型名称") {
                        TextField("", text: $model, prompt: Text("模型名称"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .accessibilityLabel("模型名称")
                    }

                    LabeledContent("API Key") {
                        SecureField(
                            "",
                            text: $apiKey,
                            prompt: Text(settings.hasAPIKey ? "已保存，留空不修改" : "API Key")
                        )
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .accessibilityLabel("API Key")
                    }

                    HStack {
                        Button("保存配置") {
                            saveConfiguration()
                        }
                        .disabled(isSaving || isTesting || isDeletingKey || isPreparingNativeLanguage)

                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Spacer()

                        if settings.hasAPIKey {
                            Button("删除 API Key", role: .destructive) {
                                deleteAPIKey()
                            }
                            .disabled(isSaving || isTesting || isDeletingKey || isPreparingNativeLanguage)
                        }
                    }

                } header: {
                    Text("大模型配置")
                } footer: {
                    Text(cloudServiceExplanation)
                }
            }

            Section("连接测试") {
                HStack {
                    Button("测试翻译") {
                        testTranslation()
                    }
                    .disabled(!canTest)

                    if isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if configurationNeedsSave, settings.engine == .llm {
                    Text("请先保存配置，再测试翻译。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("翻译与字幕")
        .macSettingsPage("翻译与字幕")
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
        .task(id: "\(settings.engine.rawValue)-\(settings.targetLanguage)") {
            guard settings.engine == .apple else { return }
            await translationService.refreshNativeLanguageStatuses()
        }
        .nativeTranslationLanguageDownloadTask(nativeLanguageDownloadRequest) { request, result in
            await completeNativeLanguageDownload(request, result: result)
        }
        .onDisappear {
            testGeneration = UUID()
            nativeLanguageGeneration = UUID()
            activeTask?.cancel()
            activeTask = nil
            isTesting = false
            isPreparingNativeLanguage = false
            nativeLanguagePairID = nil
            nativeLanguageDownloadRequest = nil
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            guard isTesting || isPreparingNativeLanguage else { return }
            testGeneration = UUID()
            nativeLanguageGeneration = UUID()
            activeTask?.cancel()
            activeTask = nil
            isTesting = false
            isPreparingNativeLanguage = false
            nativeLanguagePairID = nil
            nativeLanguageDownloadRequest = nil
            inlineMessage = nil
            testResult = nil
            translationService.clearError()
        }
    }

    private func saveConfiguration() {
        testGeneration = UUID()
        nativeLanguageGeneration = UUID()
        activeTask?.cancel()
        nativeLanguageDownloadRequest = nil
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
        nativeLanguageGeneration = UUID()
        activeTask?.cancel()
        nativeLanguageDownloadRequest = nil
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
        nativeLanguageGeneration = UUID()
        activeTask?.cancel()
        nativeLanguageDownloadRequest = nil
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
                    ?? (error as? RoomTranslationError)?.recoveryMessage(for: settings.engine)
                    ?? (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func prepareNativeLanguages(_ pair: NativeTranslationLanguagePair) {
        let generation = UUID()
        nativeLanguageGeneration = generation
        testGeneration = UUID()
        activeTask?.cancel()
        activeTask = nil
        isPreparingNativeLanguage = true
        nativeLanguagePairID = pair.id
        inlineMessage = nil
        testResult = nil
        translationService.clearError()
        nativeLanguageDownloadRequest = NativeTranslationLanguageDownloadRequest(
            id: generation,
            pair: pair
        )
    }

    @MainActor
    private func completeNativeLanguageDownload(
        _ request: NativeTranslationLanguageDownloadRequest,
        result: Result<Void, RoomTranslationError>
    ) async {
        guard
            nativeLanguageGeneration == request.id,
            nativeLanguagePairID == request.pair.id,
            settings.engine == .apple,
            settings.targetLanguage == request.pair.targetLanguage,
            !Task.isCancelled
        else { return }

        defer {
            if nativeLanguageGeneration == request.id {
                isPreparingNativeLanguage = false
                nativeLanguagePairID = nil
                nativeLanguageDownloadRequest = nil
            }
        }

        await translationService.refreshNativeLanguageStatuses()
        guard
            nativeLanguageGeneration == request.id,
            nativeLanguagePairID == request.pair.id,
            settings.engine == .apple,
            settings.targetLanguage == request.pair.targetLanguage,
            !Task.isCancelled
        else { return }

        switch result {
        case .success:
            testResult = "翻译语言包已下载"
        case .failure(let error):
            inlineMessage = error.recoveryMessage(for: settings.engine)
        }
    }

    private func resetTranslationFeedback() {
        testGeneration = UUID()
        nativeLanguageGeneration = UUID()
        activeTask?.cancel()
        isTesting = false
        isPreparingNativeLanguage = false
        nativeLanguagePairID = nil
        nativeLanguageDownloadRequest = nil
        inlineMessage = nil
        testResult = nil
        translationService.clearError()
    }
}

private struct MacTranslationSettingLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(MacTranslationSettingLabelStyle())
    }
}

private struct MacTranslationSettingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            PanelIconTile {
                configuration.icon
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            configuration.title
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct MacDanmuSettingView: View {
    var usesSettingsLayout = false
    @State private var danmuModel = DanmuSettingModel()

    var body: some View {
        Form {
            Section {
                previewCard
            }

            Section("弹幕显示") {
                MacDanmakuToggleRow(
                    title: "显示弹幕",
                    subtitle: "在直播画面上显示滚动弹幕",
                    systemImage: "bubble.left.and.bubble.right.fill",
                    tint: .green,
                    usesSettingsLayout: usesSettingsLayout,
                    isOn: $danmuModel.showDanmu
                )

                MacDanmakuToggleRow(
                    title: "彩色弹幕",
                    subtitle: "显示弹幕发送者设置的颜色",
                    systemImage: "paintpalette.fill",
                    tint: .purple,
                    usesSettingsLayout: usesSettingsLayout,
                    isOn: $danmuModel.showColorDanmu
                )
                .disabled(!danmuModel.showDanmu)
            }

            Section("外观") {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    DanmakuSettingDescriptor(
                        title: "字体大小",
                        subtitle: "仅影响之后出现的新弹幕",
                        systemImage: "textformat.size",
                        tint: .blue,
                        value: "\(danmuModel.danmuFontSize) pt"
                    )

                    Group {
                        if usesSettingsLayout {
                            Slider(value: fontSizeBinding, in: 10...100, step: 1)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                        } else {
                            Slider(value: fontSizeBinding, in: 10...100, step: 1)
                        }
                    }
                    .tint(AppConstants.Colors.accent)
                    .padding(.leading, 46)
                    .accessibilityLabel("弹幕字体大小")
                    .accessibilityValue("\(danmuModel.danmuFontSize) 点")
                }

                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    DanmakuSettingDescriptor(
                        title: "透明度",
                        subtitle: "降低透明度可以减少对画面的遮挡",
                        systemImage: "circle.lefthalf.filled",
                        tint: .orange,
                        value: String(format: "%.0f%%", danmuModel.danmuAlpha * 100)
                    )

                    Group {
                        if usesSettingsLayout {
                            Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                        } else {
                            Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
                        }
                    }
                    .tint(AppConstants.Colors.accent)
                    .padding(.leading, 46)
                    .accessibilityLabel("弹幕透明度")
                    .accessibilityValue(String(format: "%.0f%%", danmuModel.danmuAlpha * 100))
                }
            }

            Section("运动与布局") {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    DanmakuSettingDescriptor(
                        title: "移动速度",
                        subtitle: "控制弹幕从右向左通过画面的时间",
                        systemImage: "speedometer",
                        tint: .cyan
                    )

                    Picker("移动速度", selection: $danmuModel.danmuSpeedIndex) {
                        ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                            Text(DanmuSettingModel.danmuSpeedArray[index])
                                .tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .padding(.leading, 46)
                    .onChange(of: danmuModel.danmuSpeedIndex) { _, newValue in
                        danmuModel.getDanmuSpeed(index: newValue)
                    }
                }

                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    DanmakuSettingDescriptor(
                        title: "显示区域",
                        subtitle: "限制弹幕在视频画面中的覆盖范围",
                        systemImage: "rectangle.inset.filled",
                        tint: .indigo
                    )

                    Picker("显示区域", selection: $danmuModel.danmuAreaIndex) {
                        ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                            Text(DanmuSettingModel.danmuAreaArray[index])
                                .tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .padding(.leading, 46)
                }
            }

            Section {
                DanmakuKeywordBlocklistForm(settings: danmuModel)
            } header: {
                Text("关键词屏蔽")
            } footer: {
                Text("包含任一关键词的消息不会出现在聊天列表或滚动弹幕中。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("弹幕设置")
        .macSettingsPage("弹幕设置")
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(danmuModel.danmuFontSize) },
            set: { danmuModel.danmuFontSize = Int($0.rounded()) }
        )
    }

    private var previewFontSize: CGFloat {
        min(max(CGFloat(danmuModel.danmuFontSize) * 0.45, 12), 30)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
            HStack(spacing: AppConstants.Spacing.sm) {
                Label("效果预览", systemImage: "play.rectangle.fill")
                    .font(.headline)

                Spacer()

                PanelStatusBadge(
                    danmuModel.showDanmu ? "实时更新" : "已关闭",
                    tint: danmuModel.showDanmu ? AppConstants.Colors.success : .secondary
                )
            }

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.15),
                        Color(red: 0.16, green: 0.12, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(.white.opacity(0.06))

                if danmuModel.showDanmu {
                    VStack(spacing: AppConstants.Spacing.lg) {
                        HStack {
                            previewDanmaku("欢迎来到 AngelLive", color: .white)
                            Spacer(minLength: 48)
                        }

                        HStack {
                            Spacer(minLength: 72)
                            previewDanmaku("这是一条彩色弹幕", color: .cyan)
                            Spacer(minLength: 12)
                        }
                    }
                    .padding(AppConstants.Spacing.lg)
                } else {
                    Label("弹幕已关闭", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(height: 128)
            .clipShape(.rect(cornerRadius: AppConstants.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .padding(usesSettingsLayout ? 0 : AppConstants.Spacing.lg)
        .background {
            if !usesSettingsLayout {
                RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg, style: .continuous)
                    .fill(.thinMaterial)
            }
        }
    }

    private func previewDanmaku(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: previewFontSize, weight: .semibold))
            .foregroundStyle(danmuModel.showColorDanmu ? color : .white)
            .opacity(danmuModel.danmuAlpha)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.9), radius: 1, x: 1, y: 1)
    }
}

private struct MacDanmakuToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let usesSettingsLayout: Bool
    @Binding var isOn: Bool

    var body: some View {
        if usesSettingsLayout {
            PanelNavigationRow(title: title, subtitle: subtitle, showsChevron: false) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint.gradient)
            } trailing: {
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AppConstants.Colors.accent)
                    .accessibilityLabel(title)
                    .accessibilityHint(subtitle)
            }
        } else {
            Toggle(isOn: $isOn) {
                DanmakuSettingDescriptor(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage,
                    tint: tint
                )
            }
            .tint(AppConstants.Colors.accent)
        }
    }
}

private struct DanmakuSettingDescriptor: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var value: String? = nil

    var body: some View {
        HStack(spacing: AppConstants.Spacing.md) {
            PanelIconTile {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint.gradient)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppConstants.Spacing.md)

            if let value {
                Text(value)
                    .font(.callout.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.55), in: Capsule(style: .continuous))
            }
        }
    }
}

#Preview {
    #if !APPSTORE
    SettingView()
        .environmentObject(UpdaterViewModel())
    #else
    SettingView()
    #endif
}
