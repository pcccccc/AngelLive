//
//  SettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/22.
//

import SwiftUI
import AngelLiveCore

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct SettingView: View {

    @State var titles = ["账号管理", "通用设置", "弹幕设置", "数据同步", "历史记录", "开源许可", "关于"]
    @State private var selectedIndex: Int? = nil
    @State private var fullScreenIndex: Int? = nil
    @StateObject var settingStore = SettingStore()
    @Environment(AppState.self) var appViewModel
    @FocusState private var focusedIndex: Int?

    // 需要在右侧半屏显示的页面索引
    private var halfScreenIndices: Set<Int> { [0, 1, 2] } // 账号管理、通用设置、弹幕设置

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
    }

    // MARK: - 菜单列表
    private var menuListView: some View {
        VStack(spacing: 15) {
            Spacer()
            ForEach(titles.indices, id: \.self) { index in
                Button {
                    if halfScreenIndices.contains(index) {
                        selectedIndex = index
                    } else {
                        fullScreenIndex = index
                    }
                } label: {
                    HStack {
                        Text(titles[index])
                        Spacer()
                        if index == 0 {
                            Text(BilibiliCookieSyncService.shared.loginStatusDescription)
                                .font(.system(size: 30))
                                .foregroundStyle(.gray)
                        } else if index == 3 {
                            Text(appViewModel.favoriteViewModel.cloudKitReady ? "iCloud就绪" : "iCloud状态异常")
                                .font(.system(size: 30))
                                .foregroundStyle(.gray)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .focused($focusedIndex, equals: index)
            }
            Spacer(minLength: 200)
        }
    }

    // MARK: - 半屏内容视图（账号管理、通用设置、弹幕设置）
    @ViewBuilder
    private func halfScreenContentView(for index: Int) -> some View {
        switch index {
        case 0: // 账号管理
            AccountManagementView()
                .environmentObject(settingStore)
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 1: // 通用设置
            GeneralSettingView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        case 2: // 弹幕设置
            DanmuSettingMainView()
                .environment(appViewModel)
                .onExitCommand {
                    selectedIndex = nil
                }
        default:
            EmptyView()
        }
    }

    // MARK: - 全屏内容视图（数据同步、历史记录、开源许可、关于）
    @ViewBuilder
    private func fullScreenContentView(for index: Int) -> some View {
        switch index {
        case 3: // 数据同步
            if appViewModel.favoriteViewModel.cloudKitReady {
                SyncView()
                    .environment(appViewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                    .onExitCommand {
                        fullScreenIndex = nil
                    }
            } else {
                VStack {
                    Text("请通过收藏页面检查iCloud状态是否正常")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
            }
        case 4: // 历史记录
            HistoryListView(appViewModel: appViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
        case 5: // 开源许可
            NavigationStack {
                OpenSourceListView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .onExitCommand {
                fullScreenIndex = nil
            }
        case 6: // 关于
            AboutUSView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .onExitCommand {
                    fullScreenIndex = nil
                }
        default:
            EmptyView()
        }
    }
}

#Preview {
    SettingView()
}
