//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import Kingfisher
import SharedAssets

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct SettingView: View {

    @State var titles = ["账号管理", "插件管理", "通用设置", "弹幕设置", "数据同步", "历史记录", "开源许可", "清除缓存", "关于&问题反馈", "问题诊断与反馈", "翻译与字幕", "播放时间轴", "赞助商"]
    private static let sponsorsIndex = 12
    private static let platformAppearanceIndex = 13
    @State private var selectedIndex: Int? = nil
    @State private var fullScreenIndex: Int? = nil
    @State private var lastFocusedIndex: Int?
    @StateObject var settingStore = SettingStore()
    @ObservedObject private var syncService = PlatformCredentialSyncService.shared
    @State private var supportDiagnosticsService = SupportDiagnosticsService.shared
    @Environment(AppState.self) var appViewModel
    @Environment(\.usesFullUI) private var usesFullUI
    @Environment(\.supportDiagnosticsEnabled) private var supportDiagnosticsEnabled
    @FocusState private var focusedIndex: Int?
    @State private var cacheSizeText: String = "计算中..."
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false

    // 需要在右侧半屏显示的页面索引
    private var halfScreenIndices: Set<Int> { [0, 2, 3, 4, 10, Self.platformAppearanceIndex] }

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
        .onChange(of: fullScreenIndex) { previousIndex, newValue in
            guard newValue == nil else { return }
            if previousIndex == Self.sponsorsIndex {
                if shouldShowMenuItem(Self.sponsorsIndex) {
                    focusedIndex = Self.sponsorsIndex
                }
            } else if let lastFocusedIndex {
                focusedIndex = lastFocusedIndex
            }
        }
        .onChange(of: selectedIndex) { previousIndex, newIndex in
            guard appViewModel.pluginAvailability.hasAvailablePlugins,
                  newIndex == nil,
                  let previousIndex,
                  halfScreenIndices.contains(previousIndex),
                  shouldShowMenuItem(previousIndex) else { return }
            focusedIndex = previousIndex
        }
        .onChange(of: appViewModel.pluginAvailability.hasAvailablePlugins) { _, hasPlugins in
            guard !hasPlugins else { return }
            if selectedIndex == 0 {
                selectedIndex = nil
            }
            if fullScreenIndex == 1 && !canEnterPluginManagement {
                fullScreenIndex = nil
            }
            if fullScreenIndex == Self.sponsorsIndex {
                fullScreenIndex = nil
            }
            // 数据同步现在走半屏(selectedIndex),失去插件后跟着关闭
            if selectedIndex == 4 {
                selectedIndex = nil
            }
            if selectedIndex == 10 || selectedIndex == Self.platformAppearanceIndex {
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
        var fullUIOrder = indices.filter { $0 != 8 && $0 != 11 } + [8, 11]
        if let generalIndex = fullUIOrder.firstIndex(of: 2) {
            fullUIOrder.insert(Self.platformAppearanceIndex, at: generalIndex + 1)
        }
        return fullUIOrder
    }

    @ViewBuilder private var menuListView: some View {
        if appViewModel.pluginAvailability.hasAvailablePlugins {
            menuScrollView.mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 20)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20)
                }
                .padding(.horizontal, -40)
            }
        } else {
            menuScrollView
        }
    }

    private var menuScrollView: some View {
        ScrollView(.vertical) {
            VStack(spacing: 15) {
                ForEach(menuItemIndices, id: \.self) { index in
                    if shouldShowMenuItem(index) {
                        Button {
                            if index == 7 {
                                showClearCacheConfirm = true
                            } else if index == 9 || index == 11 {
                                lastFocusedIndex = focusedIndex ?? index
                                fullScreenIndex = index
                            } else if halfScreenIndices.contains(index) {
                                selectedIndex = index
                            } else {
                                if index == 1, appViewModel.pluginAvailability.hasAvailablePlugins {
                                    lastFocusedIndex = focusedIndex ?? index
                                }
                                fullScreenIndex = index
                            }
                        } label: {
                            HStack(spacing: 15) {
                                menuTitle(for: index).foregroundColor(.primary)
                                Spacer()
                                menuTrailingStatus(for: index)
                                    .lineLimit(appViewModel.pluginAvailability.hasAvailablePlugins ? 1 : nil)
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
            .padding(.vertical, appViewModel.pluginAvailability.hasAvailablePlugins ? 32 : 0)
        }
        // FullUI 的原生聚焦胶囊会超出滚动区域，保留两端放大后的完整轮廓。
        .scrollClipDisabled(appViewModel.pluginAvailability.hasAvailablePlugins)
    }

    private func menuTitle(for index: Int) -> Text {
        if index == Self.platformAppearanceIndex { return Text("配置页外观") }
        if index == 8 && appViewModel.pluginAvailability.hasAvailablePlugins { return Text("关于") }
        return Text(titles[index])
    }

    private var syncSummary: String {
        let model = appViewModel.favoriteViewModel
        guard appViewModel.pluginAvailability.hasAvailablePlugins else { return model.syncStatusDisplayText }
        guard model.favoriteICloudSyncEnabled else { return "已关闭" }
        switch model.syncStatus {
        case .syncing: return "同步中"
        case .success: return "已同步"
        case .error: return "同步失败"
        case .notLoggedIn: return "未登录"
        }
    }

    /// 菜单行尾部状态文案。抽成独立 @ViewBuilder,避免 menuListView 整体表达式过大导致编译器 type-check 超时。
    @ViewBuilder
    private func menuTrailingStatus(for index: Int) -> some View {
        let usesFullUI = appViewModel.pluginAvailability.hasAvailablePlugins
        let focused = usesFullUI && focusedIndex == index
        let statusColor: Color = usesFullUI ? (focused ? .black : .primary) : .gray
        if index == 0 {
            Text(syncService.loggedInByPluginId.values.contains(true) ? "已登录" : "未登录")
                .font(.system(size: 30))
                .foregroundStyle(statusColor)
        } else if index == 4 {
            Text(syncSummary)
                .font(.system(size: 30))
                .foregroundStyle(statusColor)
        } else if index == 7 {
            if isClearingCache {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("清理中...")
                        .font(.system(size: 30))
                        .foregroundStyle(statusColor)
                }
            } else {
                Text(cacheSizeText)
                    .font(.system(size: 30))
                    .foregroundStyle(statusColor)
            }
        } else if index == 9, supportDiagnosticsService.isRecording {
            Text("录制中")
                .font(.system(size: 30))
                .foregroundStyle(focused ? Color.black : .red)
        }
    }

    private func shouldShowMenuItem(_ index: Int) -> Bool {
        if index == 9 {
            return supportDiagnosticsEnabled
        }
        if index == 10 || index == Self.sponsorsIndex || index == Self.platformAppearanceIndex {
            return appViewModel.pluginAvailability.hasAvailablePlugins
        }
        if index == 11 {
            return appViewModel.generalSettingsViewModel.developerModeEnabled
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
            accountSettings
        case 2: // 通用设置
            GeneralSettingView(onClose: { closeHalfScreen() })
                .environment(appViewModel)
        case 3: // 弹幕设置
            if usesFullUI {
                TVFullUIDanmakuSettingsPage(onClose: { closeHalfScreen() })
                    .environment(appViewModel)
            } else {
                DanmuSettingMainView()
                    .environment(appViewModel)
                    .onExitCommand { closeHalfScreen() }
            }
        case 4: // 数据同步
            // 三端对齐:聚合 iCloud 同步 / 局域网同步 / Simple Live 老扫码同步入口。
            SyncManagementView(onBack: { closeHalfScreen() })
                .environment(appViewModel)
                .onExitCommand(perform: usesFullUI ? nil : { closeHalfScreen() })
        case 10: // 翻译与字幕
            TranslationSettingView()
                .tvFullUIBackCommand { closeHalfScreen() }
        case Self.platformAppearanceIndex where appViewModel.pluginAvailability.hasAvailablePlugins:
            TVSettingsPlatformAppearance { closeHalfScreen() }
        default:
            EmptyView()
        }
    }

    private var accountSettings: some View {
        AccountManagementView(onBack: { closeHalfScreen() })
            .environmentObject(settingStore)
            .environment(appViewModel)
            .environment(appViewModel.pluginAvailability)
            .onAppear {
                guard supportDiagnosticsEnabled else { return }
                supportDiagnosticsService.recordAction(.openedAccountManagement)
            }
            .onExitCommand(perform: usesFullUI ? nil : { closeHalfScreen() })
    }

    private func closeHalfScreen() {
        selectedIndex = nil
    }

    private func closeFullScreen() {
        fullScreenIndex = nil
    }

    // MARK: - 全屏内容视图
    @ViewBuilder
    private func fullScreenContentView(for index: Int) -> some View {
        switch index {
        case 1: // 插件管理
            pluginSettings
        case 5: // 历史记录
            HistoryListView(appViewModel: appViewModel, onClose: { closeFullScreen() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        case 6: // 开源许可
            openSourceSettings
        case 8: // 关于
            AboutUSView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .interactiveDismissDisabled(usesFullUI)
                .onExitCommand(perform: usesFullUI ? nil : { closeFullScreen() })
                .tvFullUIBackCommand(enabled: usesFullUI) { closeFullScreen() }
        case 9: // 问题诊断与反馈
            NavigationStack {
                SupportDiagnosticsView()
            }
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        case 11: // 播放时间轴
            NavigationStack {
                PlaybackTimelineView(onClose: { closeFullScreen() })
                    .navigationTitle("播放时间轴")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        case Self.sponsorsIndex:
            if appViewModel.pluginAvailability.hasAvailablePlugins {
                TVSponsorAcknowledgementsView(onClose: { closeFullScreen() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        Color.shared("sl-background")
                            .ignoresSafeArea()
                    }
                    .interactiveDismissDisabled()
                    .tvFullUIBackCommand { closeFullScreen() }
            }
        default:
            EmptyView()
        }
    }

    private var pluginSettings: some View {
        Group {
            if appViewModel.pluginAvailability.hasAvailablePlugins {
                TVFullPluginManagementView(
                    pluginSourceManager: appViewModel.pluginSourceManager,
                    pluginAvailability: appViewModel.pluginAvailability,
                    onClose: { closeFullScreen() }
                )
            } else {
                TVPluginManagementView(
                    pluginSourceManager: appViewModel.pluginSourceManager,
                    pluginAvailability: appViewModel.pluginAvailability
                )
                .onExitCommand { closeFullScreen() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear {
            guard supportDiagnosticsEnabled else { return }
            supportDiagnosticsService.recordAction(.openedPluginManagement)
        }
    }

    private var openSourceSettings: some View {
        Group {
            if appViewModel.pluginAvailability.hasAvailablePlugins {
                NavigationStack {
                    OpenSourceListView(usesFullUI: true)
                        .tvFullUIBackCommand { closeFullScreen() }
                }
                .interactiveDismissDisabled()
            } else {
                NavigationStack {
                    OpenSourceListView()
                }
                .onExitCommand { closeFullScreen() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
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

@MainActor
private protocol TVRoomTranslationSettings: AnyObject {
    var isEnabled: Bool { get set }
    var isDanmakuEnabled: Bool { get set }
    var engine: RoomTranslationEngine { get set }
    var targetLanguage: String { get set }
    var cloudBaseURL: String { get }
    var cloudModel: String { get }
    var hasAPIKey: Bool { get }
    func saveCloudConfiguration(baseURL: String, model: String, apiKey: String) throws
    func deleteAPIKey() throws
}

@MainActor
private protocol TVRoomTranslationService: AnyObject {
    var lastErrorMessage: String? { get }
    func clearError()
    func testTranslation() async throws -> String
}

extension RoomTranslationSettings: TVRoomTranslationSettings {}
extension RoomTitleTranslationService: TVRoomTranslationService {}

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
    @Environment(\.usesFullUI) private var usesFullUI
    @State private var settings: any TVRoomTranslationSettings
    @State private var translationService: any TVRoomTranslationService
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

    init() {
        _settings = State(initialValue: RoomTranslationSettings.shared)
        _translationService = State(initialValue: RoomTitleTranslationService.shared)
    }

#if DEBUG
    init(auditFixture: TVUIAuditTranslationFixture) {
        _settings = State(initialValue: auditFixture)
        _translationService = State(initialValue: auditFixture)
    }
#endif

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

    private var cloudServiceExplanation: String {
        "填写服务商提供的 API 地址（通常以 /v1 结尾），需支持 Chat Completions 接口。\n只发送待翻译文字，不上传音频；服务商可能收费。API Key 仅保存在本机。"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Toggle(isOn: Binding(
                    get: { settings.isEnabled },
                    set: { settings.isEnabled = $0 }
                )) {
                    Text("自动翻译房间标题")
                        .font(.system(size: 30, weight: .semibold))
                }
                .focused($focusedField, equals: .enabled)
                .frame(height: 55)

                Toggle(isOn: Binding(
                    get: { settings.isDanmakuEnabled },
                    set: { settings.isDanmakuEnabled = $0 }
                )) {
                    Text("自动翻译弹幕")
                        .font(.system(size: 30, weight: .semibold))
                }
                .focused($focusedField, equals: .danmakuEnabled)
                .frame(height: 55)

                VStack(alignment: .leading, spacing: 10) {
                    Text("翻译成")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)

                    Picker("翻译成", selection: Binding(
                        get: { settings.targetLanguage },
                        set: { settings.targetLanguage = $0 }
                    )) {
                        ForEach(targetLanguages) { language in
                            Text(language.name)
                                .tag(language.code)
                        }
                    }
                    .focused($focusedField, equals: .targetLanguage)
                    .frame(height: 55)
                }

                Text("自动识别标题和弹幕的语言，翻译不成功时显示原文。")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LiveSubtitleSettingsSection()
                    .environment(\.tvFullUISubtitlePresentation, usesFullUI)

                VStack(alignment: .leading, spacing: 12) {
                    Text("大模型翻译")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Apple TV 不支持系统翻译。填写下方配置，保存后点“测试翻译”。")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("API 地址")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("https://api.example.invalid/v1", text: $baseURL)
                        .focused($focusedField, equals: .baseURL)
                        .font(.system(size: 26))
                        .frame(height: 55)
                        .accessibilityLabel("API 地址")

                    Text("模型名称")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("模型名称", text: $model)
                        .focused($focusedField, equals: .model)
                        .font(.system(size: 26))
                        .frame(height: 55)
                        .accessibilityLabel("模型名称")

                    Text("API Key")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                    SecureField(settings.hasAPIKey ? "已保存，留空不修改" : "API Key", text: $apiKey)
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
                            Button("删除 API Key", role: .destructive) {
                                deleteAPIKey()
                            }
                            .focused($focusedField, equals: .delete)
                            .disabled(isSaving || isTesting || isDeletingKey)
                        }
                    }

                    Text(cloudServiceExplanation)
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if configurationNeedsSave {
                    Text("请先保存配置，再测试翻译。")
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
                    ?? (error as? RoomTranslationError)?.recoveryMessage(for: settings.engine)
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

#if DEBUG
@MainActor @Observable
final class TVUIAuditTranslationFixture: TVRoomTranslationSettings, TVRoomTranslationService {
    var isEnabled = true
    var isDanmakuEnabled = false
    var engine: RoomTranslationEngine = .llm
    var targetLanguage = "zh-Hans"
    private(set) var cloudBaseURL = "https://api.example.invalid/v1"
    private(set) var cloudModel = "fixture-model"
    private(set) var hasAPIKey = true
    var lastErrorMessage: String? { nil }

    func saveCloudConfiguration(baseURL: String, model: String, apiKey: String) throws {
        let address = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw RoomTranslationError.invalidBaseURL
        }
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RoomTranslationError.invalidModel }
        let hasReplacement = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasReplacement || (hasAPIKey && cloudBaseURL == address) else {
            throw RoomTranslationError.apiKeyRequired
        }
        cloudBaseURL = address
        cloudModel = name
        hasAPIKey = true
    }

    func deleteAPIKey() throws { hasAPIKey = false }

    func clearError() {}

    func testTranslation() async throws -> String {
        switch targetLanguage {
        case "zh-Hant": "海岸自然觀察與潮汐記錄"
        case "en": "Coastal wildlife and tide observations"
        case "ja": "海岸の自然観察と潮汐の記録"
        case "ko": "해안 자연 관찰과 조석 기록"
        default: "海岸自然观察与潮汐记录"
        }
    }
}
#endif

#Preview {
    SettingView()
}
