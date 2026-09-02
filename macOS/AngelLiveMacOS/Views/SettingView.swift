//
//  SettingView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import Kingfisher

struct SettingView: View {
    #if !APPSTORE
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    #endif
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @AppStorage(MacDockIconPreference.storageKey)
    private var dockIconPreference = MacDockIconPreference.primary

    @State private var showOpenSourceList = false
    @State private var showPluginManagement = false
    @State private var showDanmuSetting = false
    @State private var showAccountManagement = false
    @State private var showSyncManagement = false
    @State private var cacheSizeText: String = "计算中..."
    @State private var isClearingCache = false
    @State private var showClearCacheConfirm = false

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
            }

            Section("播放") {
                danmuSettingRow
            }

            Section("存储") {
                clearCacheRow
            }

            Section("关于与支持") {
                #if !APPSTORE
                checkUpdateRow
                #endif
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
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showAccountManagement = false
                            }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 480)
        }
        .sheet(isPresented: $showSyncManagement) {
            NavigationStack {
                MacSyncManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showSyncManagement = false
                            }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 520)
        }
        .sheet(isPresented: $showPluginManagement) {
            NavigationStack {
                MacPluginManagementView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                showPluginManagement = false
                            }
                        }
                    }
            }
            .frame(minWidth: 600, minHeight: 480)
        }
        .sheet(isPresented: $showOpenSourceList) {
            NavigationStack {
                OpenSourceListView()
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
        .sheet(isPresented: $showDanmuSetting) {
            NavigationStack {
                MacDanmuSettingView()
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
            .frame(width: 112)
            .onChange(of: dockIconPreference) { _, preference in
                preference.apply()
            }
            .help("macOS 仅在应用运行期间更换 Dock 图标。")
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

}

private struct MacDanmuSettingView: View {
    @State private var danmuModel = DanmuSettingModel()

    var body: some View {
        Form {
            Section {
                previewCard
            }

            Section("弹幕显示") {
                Toggle(isOn: $danmuModel.showDanmu) {
                    DanmakuSettingDescriptor(
                        title: "显示弹幕",
                        subtitle: "在直播画面上显示滚动弹幕",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        tint: .green
                    )
                }
                    .tint(AppConstants.Colors.accent)

                Toggle(isOn: $danmuModel.showColorDanmu) {
                    DanmakuSettingDescriptor(
                        title: "彩色弹幕",
                        subtitle: "显示弹幕发送者设置的颜色",
                        systemImage: "paintpalette.fill",
                        tint: .purple
                    )
                }
                    .tint(AppConstants.Colors.accent)
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

                    Slider(value: fontSizeBinding, in: 10...100, step: 1)
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

                    Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
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
        .padding(AppConstants.Spacing.lg)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg, style: .continuous))
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
