//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI
import AngelLiveCore
import Kingfisher

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct SettingView: View {

    @State var titles = ["账号管理", "插件管理", "通用设置", "弹幕设置", "数据同步", "历史记录", "开源许可", "清除缓存", "关于&问题反馈", "问题诊断与反馈", "翻译与字幕"]
    @State private var selectedIndex: Int? = nil
    @State private var fullScreenIndex: Int? = nil
    @State private var lastFocusedIndex: Int?
    @StateObject var settingStore = SettingStore()
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @State private var supportDiagnosticsService = SupportDiagnosticsService.shared
    @Environment(AppState.self) var appViewModel
    @Environment(\.supportDiagnosticsEnabled) private var supportDiagnosticsEnabled
    @FocusState private var focusedIndex: Int?
    @State private var cacheSizeText: String = "计算中..."
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false

    // 需要在右侧半屏显示的页面索引
    private var halfScreenIndices: Set<Int> { [0, 2, 3, 4, 10] } // 账号管理、通用设置、弹幕设置、数据同步、翻译与字幕

    private var canEnterPluginManagement: Bool {
        appViewModel.pluginAvailability.hasAvailablePlugins ||
        !appViewModel.pluginSourceManager.sourceURLs.isEmpty ||
        !appViewModel.pluginSourceManager.remotePlugins.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧：Logo 区域
                if selectedIndex == nil || (selectedIndex != nil && halfScreenIndices.contains(selectedIndex!)) {
                    VStack {
                        Spacer()
                        Image("icon")
                            .resizable()
                            .frame(width: 500, height: 500)
                            .cornerRadius(50)
                        Text("Angel Live")
                            .font(.headline)
                            .padding(.top, 20)
                        Text("Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))")
                            .font(.subheadline)
                        Spacer()
                    }
                    .frame(width: geometry.size.width / 2, height: geometry.size.height)
                }

                // 右侧：内容区域
                ZStack {
                    // 菜单列表
                    if selectedIndex == nil {
                        menuListView
                            .frame(width: geometry.size.width / 2 - 50)
                            .transition(.opacity)
                    }

                    // 半屏子页面内容（账号管理、通用设置、弹幕设置）
                    if let index = selectedIndex, halfScreenIndices.contains(index) {
                        halfScreenContentView(for: index)
                            .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                .padding(.trailing, 50)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedIndex)
        .fullScreenCover(item: $fullScreenIndex) { index in
            fullScreenContentView(for: index)
        }
        .onChange(of: fullScreenIndex) { _, newValue in
            guard newValue == nil, let lastFocusedIndex else { return }
            focusedIndex = lastFocusedIndex
        }
        .onChange(of: appViewModel.pluginAvailability.hasAvailablePlugins) { _, hasPlugins in
            guard !hasPlugins else { return }
            if selectedIndex == 0 {
                selectedIndex = nil
            }
            if fullScreenIndex == 1 && !canEnterPluginManagement {
                fullScreenIndex = nil
            }
            // 数据同步现在走半屏(selectedIndex),失去插件后跟着关闭
            if selectedIndex == 4 {
                selectedIndex = nil
            }
            if selectedIndex == 10 {
                selectedIndex = nil
            }
        }
        .onChange(of: appViewModel.pluginAvailability.loginRequiredInstalledPluginIds.isEmpty) { _, isEmpty in
            // 已安装插件全部不需要登录时,关闭已打开的账号管理
            if isEmpty, selectedIndex == 0 {
                selectedIndex = nil
            }
        }
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

    // MARK: - 菜单列表
    // 只调整 FullUI 的展示顺序，保留菜单索引与页面路由、焦点的对应关系。
    private var menuItemIndices: [Int] {
        let indices = Array(titles.indices)
        guard appViewModel.pluginAvailability.hasAvailablePlugins else { return indices }
        return indices.filter { $0 != 8 } + [8]
    }

    private var menuListView: some View {
        VStack(spacing: 15) {
            ForEach(menuItemIndices, id: \.self) { index in
                if shouldShowMenuItem(index) {
                    Button {
                        if index == 7 {
                            showClearCacheConfirm = true
                        } else if index == 9 {
                            lastFocusedIndex = focusedIndex ?? index
                            fullScreenIndex = index
                        } else if halfScreenIndices.contains(index) {
                            selectedIndex = index
                        } else {
                            fullScreenIndex = index
                        }
                    } label: {
                        HStack(spacing: 15) {
                            Text(index == 8 && appViewModel.pluginAvailability.hasAvailablePlugins ? "关于" : titles[index])
                                .foregroundColor(.primary)
                            Spacer()
                            menuTrailingStatus(for: index)
                            if index != 7 {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .focused($focusedIndex, equals: index)
                    .disabled(index == 7 && isClearingCache)
                }
            }
        }
    }

    /// 菜单行尾部状态文案。抽成独立 @ViewBuilder,避免 menuListView 整体表达式过大导致编译器 type-check 超时。
    @ViewBuilder
    private func menuTrailingStatus(for index: Int) -> some View {
        if index == 0 {
            Text(syncService.loggedInByPluginId.values.contains(true) ? "已登录" : "未登录")
                .font(.system(size: 30))
                .foregroundStyle(.gray)
        } else if index == 4 {
            // 三端统一文案,见 AppFavoriteModel.syncStatusDisplayText。
            Text(appViewModel.favoriteViewModel.syncStatusDisplayText)
                .font(.system(size: 30))
                .foregroundStyle(.gray)
        } else if index == 7 {
            if isClearingCache {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("清理中...")
                        .font(.system(size: 30))
                        .foregroundStyle(.gray)
                }
            } else {
                Text(cacheSizeText)
                    .font(.system(size: 30))
                    .foregroundStyle(.gray)
            }
        } else if index == 9, supportDiagnosticsService.isRecording {
            Text("录制中")
                .font(.system(size: 30))
                .foregroundStyle(.red)
        }
    }

    private func shouldShowMenuItem(_ index: Int) -> Bool {
        if index == 9 {
            return supportDiagnosticsEnabled
        }
        if index == 10 {
            return appViewModel.pluginAvailability.hasAvailablePlugins
        }
        if appViewModel.pluginAvailability.hasAvailablePlugins {
            // 已安装插件均无登录入口时,隐藏账号管理(0)
            if index == 0 {
                return !appViewModel.pluginAvailability.loginRequiredInstalledPluginIds.isEmpty
            }
            return true
        }
        if index == 1 {
            return canEnterPluginManagement
        }
        // 无本地插件时隐藏：账号管理(0)、数据同步(4)
        return index != 0 && index != 4
    }

    // MARK: - 半屏内容视图（账号管理、通用设置、弹幕设置）
    @ViewBuilder
    private func halfScreenContentView(for index: Int) -> some View {
        switch index {
        case 0: // 账号管理
            AccountManagementView()
                .environmentObject(settingStore)
                .environment(appViewModel)
                .environment(appViewModel.pluginAvailability)
                .onAppear {
                    guard supportDiagnosticsEnabled else { return }
                    supportDiagnosticsService.recordAction(.openedAccountManagement)
                }
                .onExitCommand {
                    selectedIndex = nil
                }
        case 2: // 通用设置
            GeneralSettingView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 3: // 弹幕设置
            DanmuSettingMainView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 4: // 数据同步
            // 三端对齐:聚合 iCloud 同步 / 局域网同步 / Simple Live 老扫码同步入口。
            SyncManagementView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 10: // 翻译与字幕
            TranslationSettingView()
                .onExitCommand {
                    selectedIndex = nil
                }
        default:
            EmptyView()
        }
    }

    // MARK: - 全屏内容视图（插件管理、历史记录、开源许可、关于）
    @ViewBuilder
    private func fullScreenContentView(for index: Int) -> some View {
        switch index {
        case 1: // 插件管理
            Group {
                if appViewModel.pluginAvailability.hasAvailablePlugins {
                    TVFullPluginManagementView(
                        pluginSourceManager: appViewModel.pluginSourceManager,
                        pluginAvailability: appViewModel.pluginAvailability,
                        onClose: { fullScreenIndex = nil }
                    )
                } else {
                    TVPluginManagementView(
                        pluginSourceManager: appViewModel.pluginSourceManager,
                        pluginAvailability: appViewModel.pluginAvailability
                    )
                    .onExitCommand {
                        fullScreenIndex = nil
                    }
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onAppear {
                    guard supportDiagnosticsEnabled else { return }
                    supportDiagnosticsService.recordAction(.openedPluginManagement)
                }
        case 5: // 历史记录
            HistoryListView(appViewModel: appViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
        case 6: // 开源许可
            NavigationStack {
                OpenSourceListView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .onExitCommand {
                fullScreenIndex = nil
            }
        case 8: // 关于
            AboutUSView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
        case 9: // 问题诊断与反馈
            NavigationStack {
                SupportDiagnosticsView()
            }
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        default:
            EmptyView()
        }
    }

    // MARK: - 缓存维护
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
            imageCache: Self.kingfisherBridge,
            // tvOS 清理后立即同步到 App Group,让 TopShelf 看到的也是清理后的状态
            extraWork: { PluginAppGroupSync.syncToAppGroup() }
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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case enabled
        case danmakuEnabled
        case targetLanguage
        case baseURL
        case model
        case apiKey
        case save
        case delete
        case test
    }

    private var configurationNeedsSave: Bool {
        let normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedBaseURL != settings.cloudBaseURL
            || normalizedModel != settings.cloudModel
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTest: Bool {
        guard !isSaving, !isTesting, !isDeletingKey else { return false }
        return !configurationNeedsSave
            && settings.hasAPIKey
            && !settings.cloudBaseURL.isEmpty
            && !settings.cloudModel.isEmpty
    }

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Toggle(isOn: $settings.isEnabled) {
                    Text("自动翻译房间标题")
                        .font(.system(size: 30, weight: .semibold))
                }
                .focused($focusedField, equals: .enabled)
                .frame(height: 55)

                Toggle(isOn: $settings.isDanmakuEnabled) {
                    Text("自动翻译弹幕")
                        .font(.system(size: 30, weight: .semibold))
                }
                .focused($focusedField, equals: .danmakuEnabled)
                .frame(height: 55)

                VStack(alignment: .leading, spacing: 10) {
                    Text("目标语言")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("目标语言", selection: $settings.targetLanguage) {
                        ForEach(targetLanguages) { language in
                            Text(language.name)
                                .tag(language.code)
                        }
                    }
                    .focused($focusedField, equals: .targetLanguage)
                    .frame(height: 55)
                }

                Text("翻译成功显示译文，失败或来不及翻译保留原文；图文弹幕保留图片表情。")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    Text("翻译引擎")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Apple TV 仅支持兼容 AI 接口。")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("服务地址")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("https://api.example.invalid/v1", text: $baseURL)
                        .focused($focusedField, equals: .baseURL)
                        .font(.system(size: 26))
                        .frame(height: 55)
                        .accessibilityLabel("服务地址")

                    Text("模型")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("模型名称", text: $model)
                        .focused($focusedField, equals: .model)
                        .font(.system(size: 26))
                        .frame(height: 55)
                        .accessibilityLabel("模型")

                    Text("API Key")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    SecureField(settings.hasAPIKey ? "留空保持已保存密钥" : "API Key", text: $apiKey)
                        .focused($focusedField, equals: .apiKey)
                        .font(.system(size: 26))
                        .frame(height: 55)
                        .accessibilityLabel("API Key")

                    HStack(spacing: 18) {
                        Button {
                            saveConfiguration()
                        } label: {
                            HStack(spacing: 10) {
                                Text("保存配置")
                                if isSaving {
                                    ProgressView()
                                }
                            }
                        }
                        .focused($focusedField, equals: .save)
                        .disabled(isSaving || isTesting || isDeletingKey)

                        if settings.hasAPIKey {
                            Button("删除已保存密钥", role: .destructive) {
                                deleteAPIKey()
                            }
                            .focused($focusedField, equals: .delete)
                            .disabled(isSaving || isTesting || isDeletingKey)
                        }
                    }

                    Text("开启对应开关后，房间标题或弹幕文本会发送至你配置的服务。弹幕频率较高，可能增加用量或费用；不会发送用户名或图片 URL。API Key 只保存在本机安全存储中。")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if configurationNeedsSave {
                    Text("请先保存接口配置，再测试翻译。")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

                Button {
                    testTranslation()
                } label: {
                    HStack(spacing: 10) {
                        Text("测试翻译")
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .focused($focusedField, equals: .test)
                .disabled(!canTest)

                if let inlineMessage {
                    Text(inlineMessage)
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let serviceError = translationService.lastErrorMessage {
                    Text(serviceError)
                        .font(.system(size: 22))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let testResult {
                    Text("结果：\(testResult)")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.vertical, 45)
            .padding(.horizontal, 60)
        }
        .scrollClipDisabled()
        .onAppear {
            if settings.engine != .llm {
                settings.engine = .llm
            }
            baseURL = settings.cloudBaseURL
            model = settings.cloudModel
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

#Preview {
    SettingView()
}
