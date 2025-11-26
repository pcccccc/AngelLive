//
//  SettingView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct SettingView: View {
    @StateObject private var settingStore = SettingStore()
    @State private var cloudKitReady = false
    @State private var cloudKitStateString = "检查中..."

    var body: some View {
        NavigationStack {
            List {
                // 账号设置（暂时隐藏）
                // Section {
                //     NavigationLink {
                //         BilibiliLoginViewiOS()
                //     } label: {
                //         HStack {
                //             Image(systemName: "person.circle.fill")
                //                 .font(.title3)
                //                 .foregroundStyle(AppConstants.Colors.link.gradient)
                //                 .frame(width: 32)
                //
                //             Text("哔哩哔哩登录")
                //
                //             Spacer()
                //
                //             Text(settingStore.bilibiliCookie.isEmpty ? "未登录" : "已登录")
                //                 .font(.caption)
                //                 .foregroundStyle(AppConstants.Colors.secondaryText)
                //         }
                //     }
                // } header: {
                //     Text("账号")
                // }

                // 应用设置
                Section {
                    NavigationLink {
                        GeneralSettingViewiOS()
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
                        DanmuSettingViewiOS()
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.success.gradient)
                                .frame(width: 32)
                            Text("弹幕设置")
                        }
                    }
                } header: {
                    Text("设置")
                }

                // 数据管理
                Section {
                    NavigationLink {
                        if cloudKitReady {
                            SyncViewiOS()
                        } else {
                            CloudKitStatusView(stateString: cloudKitStateString)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "icloud.fill")
                                .font(.title3)
                                .foregroundStyle(Color.cyan.gradient)
                                .frame(width: 32)

                            Text("数据同步")

                            Spacer()

                            Text(cloudKitReady ? "iCloud 就绪" : "状态异常")
                                .font(.caption)
                                .foregroundStyle(cloudKitReady ? AppConstants.Colors.success : AppConstants.Colors.error)
                        }
                    }

                    NavigationLink {
                        HistoryListViewiOS()
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
                    Text("数据")
                }

                // 关于
                Section {
                    NavigationLink {
                        OpenSourceListViewiOS()
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
                        AboutUSViewiOS()
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
                await checkCloudKitStatus()
            }
        }
    }

    private func checkCloudKitStatus() async {
        cloudKitStateString = await FavoriteService.getCloudState()
        cloudKitReady = cloudKitStateString == "正常"
    }
}

// MARK: - Placeholder Views
struct BilibiliLoginViewiOS: View {
    @StateObject private var settingStore = SettingStore()
    @State private var qrcodeUrl = ""
    @State private var qrcodeKey = ""
    @State private var message = "正在加载二维码..."
    @State private var loginSuccess = false
    @State private var timer: Timer?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.xl) {
                if loginSuccess {
                    // 登录成功状态
                    VStack(spacing: AppConstants.Spacing.lg) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(AppConstants.Colors.success.gradient)

                        Text("登录成功")
                            .font(.title.bold())
                            .foregroundStyle(AppConstants.Colors.primaryText)

                        Text("您已成功登录哔哩哔哩账号")
                            .font(.body)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                            .multilineTextAlignment(.center)

                        Button {
                            // 退出登录
                            settingStore.bilibiliCookie = ""
                            loginSuccess = false
                            Task {
                                await getQRCode()
                            }
                        } label: {
                            Text("退出登录")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppConstants.Colors.error.gradient)
                                .cornerRadius(AppConstants.CornerRadius.md)
                        }
                        .padding(.horizontal)
                        .padding(.top, AppConstants.Spacing.lg)
                    }
                    .padding(.top, AppConstants.Spacing.xxl)
                } else {
                    // 二维码登录状态
                    VStack(spacing: AppConstants.Spacing.lg) {
                        Text("扫码登录")
                            .font(.title2.bold())
                            .foregroundStyle(AppConstants.Colors.primaryText)

                        // 二维码区域
                        VStack(spacing: AppConstants.Spacing.md) {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .frame(width: 250, height: 250)
                            } else {
                                Image(uiImage: QRCodeGenerator.generateQRCode(from: qrcodeUrl))
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 250, height: 250)
                                    .background(Color.white)
                                    .cornerRadius(AppConstants.CornerRadius.lg)
                                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            }

                            // 刷新按钮
                            Button {
                                Task {
                                    await getQRCode()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("刷新二维码")
                                }
                                .font(.subheadline)
                                .foregroundStyle(AppConstants.Colors.link)
                            }
                        }
                        .padding(AppConstants.Spacing.lg)
                        .background(AppConstants.Colors.materialBackground)
                        .cornerRadius(AppConstants.CornerRadius.lg)

                        // 状态提示
                        VStack(spacing: AppConstants.Spacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.link.gradient)

                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(AppConstants.Colors.materialBackground)
                        .cornerRadius(AppConstants.CornerRadius.md)

                        // 使用说明
                        VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                            Text("使用说明")
                                .font(.headline)
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                                HStack(alignment: .top, spacing: AppConstants.Spacing.sm) {
                                    Text("1.")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                    Text("打开哔哩哔哩 APP")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }

                                HStack(alignment: .top, spacing: AppConstants.Spacing.sm) {
                                    Text("2.")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                    Text("扫描上方二维码")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }

                                HStack(alignment: .top, spacing: AppConstants.Spacing.sm) {
                                    Text("3.")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                    Text("在手机上确认授权登录")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppConstants.Colors.materialBackground)
                        .cornerRadius(AppConstants.CornerRadius.md)
                    }
                    .padding(.top, AppConstants.Spacing.md)
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("哔哩哔哩")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 检查是否已登录
            if !settingStore.bilibiliCookie.isEmpty {
                loginSuccess = true
            } else {
                await getQRCode()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    func getQRCode() async {
        isLoading = true
        message = "正在加载二维码..."
        do {
            let dataReq = try await Bilibili.getQRCodeUrl()
            if dataReq.code == 0 {
                qrcodeKey = dataReq.data.qrcode_key ?? ""
                qrcodeUrl = dataReq.data.url ?? ""
                isLoading = false
                message = "请打开哔哩哔哩 APP 扫描二维码"

                // 启动定时器检查登录状态
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    Task {
                        await getQRCodeScanState()
                    }
                }
            } else {
                isLoading = false
                message = dataReq.message
            }
        } catch {
            isLoading = false
            message = "加载失败，请点击刷新重试"
            print("获取二维码失败: \(error)")
        }
    }

    func getQRCodeScanState() async {
        if loginSuccess {
            return
        }

        do {
            let dataReq = try await Bilibili.getQRCodeState(qrcode_key: qrcodeKey)
            let code = dataReq.0.data.code

            switch code {
            case 86090:
                message = "扫描成功，请在手机上确认授权"
            case 86038:
                message = "二维码已过期，请点击刷新重试"
                timer?.invalidate()
            case 0:
                message = "登录成功"
                settingStore.bilibiliCookie = dataReq.1
                loginSuccess = true
                timer?.invalidate()
            case 86101:
                message = "请打开哔哩哔哩 APP 扫描二维码"
            default:
                message = "未知状态，请刷新重试"
            }
        } catch {
            print("检查登录状态失败: \(error)")
            timer?.invalidate()
        }
    }
}

struct GeneralSettingViewiOS: View {
    @State private var playerSettingModel = PlayerSettingModel()
    @State private var generalSettingModel = GeneralSettingModel()
    @StateObject private var settingStore = SettingStore()

    var body: some View {
        List {
            // 播放设置
            Section {
                Toggle("直播结束后自动退出直播间", isOn: $playerSettingModel.openExitPlayerViewWhenLiveEnd)

                if playerSettingModel.openExitPlayerViewWhenLiveEnd {
                    Picker("自动退出直播间时间", selection: $playerSettingModel.openExitPlayerViewWhenLiveEndSecondIndex) {
                        ForEach(PlayerSettingModel.timeArray.indices, id: \.self) { index in
                            Text(PlayerSettingModel.timeArray[index])
                                .tag(index)
                        }
                    }
                    .onChange(of: playerSettingModel.openExitPlayerViewWhenLiveEndSecondIndex) { _, newValue in
                        playerSettingModel.getTimeSecond(index: newValue)
                    }
                }
            } header: {
                Text("播放设置")
            }

            // 通用设置
            Section {
                Toggle("匹配系统帧率", isOn: $settingStore.syncSystemRate)

                Toggle("禁用渐变背景", isOn: $generalSettingModel.generalDisableMaterialBackground)
            } header: {
                Text("通用设置")
            } footer: {
                Text("如果您的页面部分背景不正常（如页面背景透明），请尝试打开这个选项。")
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }

            // 收藏设置
            Section {
                Picker("收藏页面展示样式", selection: $generalSettingModel.globalGeneralSettingFavoriteStyle) {
                    ForEach(AngelLiveFavoriteStyle.allCases, id: \.self) { style in
                        Text(style.description)
                            .tag(style.rawValue)
                    }
                }
            } header: {
                Text("收藏设置")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DanmuSettingViewiOS: View {
    @State private var danmuModel = DanmuSettingModel()
    @State private var alphaText = ""

    var body: some View {
        List {
            // 基本设置
            Section {
                Toggle("开启弹幕", isOn: $danmuModel.showDanmu)

                Toggle("开启彩色弹幕", isOn: $danmuModel.showColorDanmu)
            } header: {
                Text("基本设置")
            }

            // 字体设置
            Section {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    HStack {
                        Text("字体大小")
                            .foregroundStyle(AppConstants.Colors.primaryText)
                        Spacer()
                        Text("\(danmuModel.danmuFontSize)")
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }

                    HStack(spacing: AppConstants.Spacing.md) {
                        Button {
                            if danmuModel.danmuFontSize > 15 {
                                danmuModel.danmuFontSize -= 5
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppConstants.Colors.error.gradient)
                        }

                        Button {
                            if danmuModel.danmuFontSize > 10 {
                                danmuModel.danmuFontSize -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.warning.gradient)
                        }

                        Spacer()

                        Text("这是测试弹幕")
                            .font(.system(size: CGFloat(danmuModel.danmuFontSize)))
                            .foregroundStyle(AppConstants.Colors.primaryText)

                        Spacer()

                        Button {
                            if danmuModel.danmuFontSize < 100 {
                                danmuModel.danmuFontSize += 1
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .foregroundStyle(AppConstants.Colors.success.gradient)
                        }

                        Button {
                            if danmuModel.danmuFontSize < 95 {
                                danmuModel.danmuFontSize += 5
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppConstants.Colors.link.gradient)
                        }
                    }
                }
                .padding(.vertical, AppConstants.Spacing.sm)
            } header: {
                Text("字体设置")
            }

            // 显示设置
            Section {
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    HStack {
                        Text("透明度")
                        Spacer()
                        Text(String(format: "%.1f", danmuModel.danmuAlpha))
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }

                    Slider(value: $danmuModel.danmuAlpha, in: 0.1...1.0, step: 0.1)
                        .tint(AppConstants.Colors.link)
                }

                Picker("弹幕速度", selection: $danmuModel.danmuSpeedIndex) {
                    ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                        Text(DanmuSettingModel.danmuSpeedArray[index])
                            .tag(index)
                    }
                }
                .onChange(of: danmuModel.danmuSpeedIndex) { _, newValue in
                    danmuModel.getDanmuSpeed(index: newValue)
                }

                Picker("显示区域", selection: $danmuModel.danmuAreaIndex) {
                    ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                        Text(DanmuSettingModel.danmuAreaArray[index])
                            .tag(index)
                    }
                }
            } header: {
                Text("显示设置")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("弹幕")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            alphaText = String(format: "%.1f", danmuModel.danmuAlpha)
        }
    }
}

struct SyncViewiOS: View {
    @Environment(AppFavoriteModel.self) var favoriteModel
    @State private var isSyncing = false
    @State private var showSyncResult = false
    @State private var syncResultMessage = ""
    @State private var syncSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.lg) {
                // iCloud 状态卡片
                VStack(spacing: AppConstants.Spacing.md) {
                    HStack {
                        Image(systemName: statusIcon)
                            .font(.title)
                            .foregroundStyle(statusColor.gradient)
                            .frame(width: 50)

                        VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                            Text("iCloud 状态")
                                .font(.headline)
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }

                        Spacer()
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 同步统计卡片
                VStack(spacing: AppConstants.Spacing.md) {
                    Text("同步数据统计")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: AppConstants.Spacing.lg) {
                        // 收藏数量
                        VStack(spacing: AppConstants.Spacing.xs) {
                            Text("\(favoriteModel.roomList.count)")
                                .font(.title.bold())
                                .foregroundStyle(AppConstants.Colors.link.gradient)

                            Text("收藏主播")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppConstants.Colors.materialBackground.opacity(0.5))
                        .cornerRadius(AppConstants.CornerRadius.md)

                        // 分组数量
                        VStack(spacing: AppConstants.Spacing.xs) {
                            Text("\(favoriteModel.groupedRoomList.count)")
                                .font(.title.bold())
                                .foregroundStyle(AppConstants.Colors.success.gradient)

                            Text("平台分组")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppConstants.Colors.materialBackground.opacity(0.5))
                        .cornerRadius(AppConstants.CornerRadius.md)
                    }

                    // 上次同步时间
                    if let lastSync = favoriteModel.lastSyncTime {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                            Text("上次同步：\(formatDate(lastSync))")
                                .font(.caption)
                                .foregroundStyle(AppConstants.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 同步进度卡片
                if isSyncing {
                    VStack(spacing: AppConstants.Spacing.md) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在同步...")
                                .font(.subheadline)
                                .foregroundStyle(AppConstants.Colors.primaryText)
                        }

                        if !favoriteModel.syncProgressInfo.0.isEmpty {
                            VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                                HStack {
                                    Text(favoriteModel.syncProgressInfo.0)
                                        .font(.caption)
                                        .foregroundStyle(AppConstants.Colors.primaryText)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(favoriteModel.syncProgressInfo.2)
                                        .font(.caption)
                                        .foregroundStyle(
                                            favoriteModel.syncProgressInfo.2 == "成功" ?
                                            AppConstants.Colors.success :
                                                AppConstants.Colors.error
                                        )
                                }

                                Text(favoriteModel.syncProgressInfo.1)
                                    .font(.caption2)
                                    .foregroundStyle(AppConstants.Colors.secondaryText)

                                ProgressView(
                                    value: Double(favoriteModel.syncProgressInfo.3),
                                    total: Double(favoriteModel.syncProgressInfo.4)
                                )
                                .tint(AppConstants.Colors.link)
                            }
                        }
                    }
                    .padding()
                    .background(AppConstants.Colors.materialBackground)
                    .cornerRadius(AppConstants.CornerRadius.lg)
                }

                // 手动同步按钮
                Button {
                    Task {
                        await performSync()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(isSyncing ? "同步中..." : "立即同步")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        isSyncing ?
                        Color.gray.gradient :
                        AppConstants.Colors.link.gradient
                    )
                    .cornerRadius(AppConstants.CornerRadius.md)
                }
                .disabled(isSyncing || !favoriteModel.cloudKitReady)

                // 使用说明
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Text("关于 iCloud 同步")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    VStack(alignment: .leading, spacing: AppConstants.Spacing.xs) {
                        Label("收藏数据会自动同步到 iCloud", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("所有登录同一 iCloud 账号的设备共享收藏", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("下拉收藏页面可快速刷新数据", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)

                        Label("删除收藏后会自动从 iCloud 移除", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppConstants.Colors.secondaryText)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                Spacer(minLength: AppConstants.Spacing.xxl)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("数据同步")
        .navigationBarTitleDisplayMode(.inline)
        .alert(syncSuccess ? "同步成功" : "同步失败", isPresented: $showSyncResult) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(syncResultMessage)
        }
    }

    private var statusIcon: String {
        switch favoriteModel.syncStatus {
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.icloud.fill"
        case .error:
            return "exclamationmark.icloud.fill"
        case .notLoggedIn:
            return "xmark.icloud.fill"
        }
    }

    private var statusColor: Color {
        switch favoriteModel.syncStatus {
        case .syncing:
            return AppConstants.Colors.link
        case .success:
            return AppConstants.Colors.success
        case .error:
            return AppConstants.Colors.error
        case .notLoggedIn:
            return AppConstants.Colors.warning
        }
    }

    private var statusText: String {
        if isSyncing {
            return "正在同步数据..."
        }

        switch favoriteModel.syncStatus {
        case .syncing:
            return "正在同步..."
        case .success:
            return "iCloud 已就绪，数据已同步"
        case .error:
            return favoriteModel.cloudKitStateString
        case .notLoggedIn:
            return "未登录 iCloud，请前往系统设置登录"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func performSync() async {
        isSyncing = true
        await favoriteModel.syncWithActor()
        isSyncing = false

        if favoriteModel.syncStatus == .success {
            syncSuccess = true
            syncResultMessage = "成功同步 \(favoriteModel.roomList.count) 个收藏"
        } else {
            syncSuccess = false
            syncResultMessage = favoriteModel.cloudKitStateString
        }
        showSyncResult = true
    }
}

struct HistoryListViewiOS: View {
    @State private var historyModel = HistoryModel()
    @State private var showClearAlert = false
    @State private var selectedRoom: LiveModel?
    @State private var showDeleteAlert = false

    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: AppConstants.Spacing.md)
    ]

    var body: some View {
        ZStack {
            if historyModel.watchList.isEmpty {
                // 空状态视图
                VStack(spacing: AppConstants.Spacing.lg) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundStyle(AppConstants.Colors.secondaryText.opacity(0.5))

                    Text("暂无观看记录")
                        .font(.title3)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("开始观看直播后会显示在这里")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppConstants.Spacing.lg) {
                        ForEach(historyModel.watchList, id: \.roomId) { room in
                            LiveRoomCard(room: room)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        selectedRoom = room
                                        showDeleteAlert = true
                                    } label: {
                                        Label("删除此记录", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !historyModel.watchList.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearAlert = true
                    } label: {
                        Text("清空")
                            .foregroundStyle(AppConstants.Colors.error)
                    }
                }
            }
        }
        .alert("清空历史记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                historyModel.clearAll()
            }
        } message: {
            Text("确定要清空所有观看记录吗？此操作不可恢复。")
        }
        .alert("删除记录", isPresented: $showDeleteAlert) {
            Button("取消", role: .cancel) {
                selectedRoom = nil
            }
            Button("删除", role: .destructive) {
                if let room = selectedRoom {
                    historyModel.removeHistory(room: room)
                    selectedRoom = nil
                }
            }
        } message: {
            if let room = selectedRoom {
                Text("确定要删除 \(room.userName) 的观看记录吗？")
            }
        }
    }
}

struct OpenSourceListViewiOS: View {
    @State private var acknowList: AcknowList? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: AppConstants.Spacing.lg) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("加载开源许可...")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMsg = errorMessage {
                VStack(spacing: AppConstants.Spacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(AppConstants.Colors.warning.gradient)

                    Text("无法加载开源许可")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let list = acknowList {
                AcknowListSwiftUIView(acknowList: list)
            } else {
                VStack(spacing: AppConstants.Spacing.lg) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(AppConstants.Colors.secondaryText.opacity(0.5))

                    Text("暂无开源许可信息")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadAcknowledgements()
        }
    }

    private func loadAcknowledgements() {
        isLoading = true
        errorMessage = nil

        // 尝试从 Bundle 中加载 Package.resolved 文件
        guard let url = Bundle.main.url(forResource: "Package", withExtension: "resolved") else {
            errorMessage = "找不到 Package.resolved 文件"
            isLoading = false
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = AcknowPackageDecoder()
            let list = try decoder.decode(from: data)
            acknowList = list
            isLoading = false
        } catch {
            errorMessage = "解析失败: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

struct AboutUSViewiOS: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Spacing.xl) {
                // 应用图标和名称
                VStack(spacing: AppConstants.Spacing.md) {
                    Image("icon")
                        .resizable()
                        .frame(width: 120, height: 120)
                        .cornerRadius(AppConstants.CornerRadius.xl)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

                    Text("AngelLive")
                        .font(.title.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("版本 \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .padding(.top, AppConstants.Spacing.xl)

                // 项目描述
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Text("关于 AngelLive")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("一个简洁、优雅的多平台直播聚合应用，支持哔哩哔哩、斗鱼、虎牙等多个直播平台。")
                        .font(.body)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 项目地址
                VStack(spacing: AppConstants.Spacing.md) {
                    Text("项目地址 & 问题反馈")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: AppConstants.Spacing.lg) {
                        // GitHub 二维码
                        VStack(spacing: AppConstants.Spacing.sm) {
                            Image("qrcode-github")
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 140, height: 140)
                                .background(Color.white)
                                .cornerRadius(AppConstants.CornerRadius.md)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)

                            Text("GitHub")
                                .font(.caption.bold())
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Button {
                                if let url = URL(string: "https://github.com/pcccccc/AngelLive") {
                                    openURL(url)
                                }
                            } label: {
                                Text("访问项目")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.link)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Telegram 二维码
                        VStack(spacing: AppConstants.Spacing.sm) {
                            Image("qrcode-telegram")
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 140, height: 140)
                                .background(Color.white)
                                .cornerRadius(AppConstants.CornerRadius.md)
                                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)

                            Text("Telegram")
                                .font(.caption.bold())
                                .foregroundStyle(AppConstants.Colors.primaryText)

                            Button {
                                if let url = URL(string: "https://t.me/SimpleLiveTV") {
                                    openURL(url)
                                }
                            } label: {
                                Text("加入群组")
                                    .font(.caption)
                                    .foregroundStyle(AppConstants.Colors.link)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 功能特性
                VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                    Text("功能特性")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                        FeatureRow(icon: "sparkles", title: "多平台支持", description: "支持哔哩哔哩、斗鱼、虎牙等直播平台")
                        FeatureRow(icon: "icloud.fill", title: "iCloud 同步", description: "收藏数据跨设备自动同步")
                        FeatureRow(icon: "bubble.left.and.bubble.right.fill", title: "实时弹幕", description: "支持弹幕显示和自定义设置")
                        FeatureRow(icon: "heart.fill", title: "收藏功能", description: "快速收藏喜欢的主播")
                        FeatureRow(icon: "magnifyingglass", title: "搜索发现", description: "搜索和发现精彩直播")
                    }
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 免责声明
                VStack(alignment: .leading, spacing: AppConstants.Spacing.sm) {
                    Text("免责声明")
                        .font(.headline)
                        .foregroundStyle(AppConstants.Colors.primaryText)

                    Text("本软件完全免费，仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关！")
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(AppConstants.Colors.materialBackground)
                .cornerRadius(AppConstants.CornerRadius.lg)

                // 版权信息
                VStack(spacing: AppConstants.Spacing.xs) {
                    Text("© 2024 AngelLive")
                        .font(.caption2)
                        .foregroundStyle(AppConstants.Colors.secondaryText)

                    Text("Made with ♥ by the community")
                        .font(.caption2)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                }
                .padding(.vertical, AppConstants.Spacing.lg)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: AppConstants.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppConstants.Colors.link.gradient)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
    }
}

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
