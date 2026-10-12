//
//  FavoriteView.swift
//  AngelLive
//
//  收藏列表 - 使用 UICollectionView 实现
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import UIKit

struct FavoriteView: View {
    @Environment(AppFavoriteModel.self) private var viewModel
    let embeddedInNavigationStack: Bool
    @State private var searchText = ""
    @State private var showsCloudSyncDetails = false
    @State private var pullDistance: CGFloat = 0
    @State private var isPullRefreshing = false
    @State private var refreshCycle = 0
    /// 共享导航状态 - 在 PiP 背景/前台切换时保持稳定
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace
    private static var lastLeaveTimestamp: Date?
    private static let syncCooldown: TimeInterval = 180

    init(embeddedInNavigationStack: Bool = false) {
        self.embeddedInNavigationStack = embeddedInNavigationStack
    }

    var body: some View {
        playerPresentation
            .overlay(alignment: .top) {
                LiquidRefreshIndicator(
                    pullDistance: pullDistance,
                    isRefreshing: isPullRefreshing || viewModel.isFavoriteStatusRefreshing,
                    refreshCycle: refreshCycle,
                    accessibilityTitle: "正在刷新收藏"
                )
            }
            .searchable(text: $searchText, prompt: "搜索主播名或房间标题")
            .task {
                await loadIfNeeded()
            }
            .onDisappear {
                FavoriteView.lastLeaveTimestamp = Date()
                pullDistance = 0
            }
    }

    @ViewBuilder
    private var playerPresentation: some View {
        if #available(iOS 18.0, *) {
            if embeddedInNavigationStack {
                favoriteList
                    .fullScreenCover(isPresented: playerPresentedBinding) {
                        playerDestination
                    }
            } else {
                baseNavigation
                    .fullScreenCover(isPresented: playerPresentedBinding) {
                        playerDestination
                    }
            }
        } else {
            if embeddedInNavigationStack {
                favoriteList
                    .navigationDestination(isPresented: playerPresentedBinding) {
                        playerDestination
                    }
            } else {
                // iOS 17: navigationDestination 必须在 NavigationStack 内部
                NavigationStack {
                    favoriteList
                        .navigationDestination(isPresented: playerPresentedBinding) {
                            playerDestination
                        }
                }
            }
        }
    }

    private var baseNavigation: some View {
        NavigationStack {
            favoriteList
                .fullUITabBarVisibilityRoot()
        }
    }

    /// 收藏列表主体(UIKit 集合视图包装 + 安全区域/大标题处理),iOS 17/18 共用。
    private var favoriteList: some View {
        FavoriteListViewControllerWrapper(
            searchText: searchText,
            navigationState: navigationState,
            namespace: roomTransitionNamespace,
            onPullDistanceChange: { pullDistance = $0 },
            onRefreshChange: { refreshing in
                if refreshing { refreshCycle += 1 }
                isPullRefreshing = refreshing
            }
        )
        // 安全区域处理 - 同时支持 TabBar 透视和大标题动画
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 0) }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        // Preserve the original large-title collapse behavior.
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.cloudReturnError, !viewModel.roomList.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("云同步暂不可用", systemImage: "icloud.slash") {
                        showsCloudSyncDetails = true
                    }
                    .accessibilityHint("本地收藏仍可使用，查看同步说明")
                }
            }
        }
        .sheet(isPresented: $showsCloudSyncDetails) {
            NavigationStack {
                FavoriteCloudUnavailableView(
                    statusMessage: viewModel.cloudKitStateString,
                    syncError: viewModel.lastSyncError,
                    hasLocalFavorites: !viewModel.roomList.isEmpty,
                    isRefreshing: viewModel.isCloudSyncing,
                    onRetry: {
                        Task { await viewModel.pullToRefresh() }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsCloudSyncDetails = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: viewModel.cloudKitReady) { _, isReady in
            if isReady { showsCloudSyncDetails = false }
        }
    }

    private var playerPresentedBinding: Binding<Bool> {
        Binding(
            get: { navigationState.showPlayer },
            set: { navigationState.showPlayer = $0 }
        )
    }

    @ViewBuilder
    private var playerDestination: some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms
            )
                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: roomTransitionNamespace))
                .fullUITabBarHidden()
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        if shouldSkipSyncAfterReturn() {
            return
        }
        if viewModel.shouldSync() {
            await viewModel.syncWithActor()
        }
    }

    private func shouldSkipSyncAfterReturn() -> Bool {
        guard let lastLeave = FavoriteView.lastLeaveTimestamp else {
            return false
        }
        let timeSinceLeave = Date().timeIntervalSince(lastLeave)
        return timeSinceLeave < FavoriteView.syncCooldown
    }
}

/// FullUI presents account guidance locally; shared sync state and ShellUI keep their existing behavior.
struct FavoriteCloudUnavailableView: View {
    let statusMessage: String
    let syncError: SyncError?
    let hasLocalFavorites: Bool
    let isRefreshing: Bool
    let onRetry: () -> Void
    @State private var showsSignInInstructions = false

    private var needsSignIn: Bool {
        // The legacy account-status path still supplies a string rather than SyncError.
        syncError?.kind == .notSignedIn || statusMessage.hasPrefix("未登录")
    }

    private var explanation: String {
        if needsSignIn {
            return "尚未登录 iCloud，暂时无法同步其他设备上的收藏。"
        }
        return statusMessage.replacingOccurrences(
            of: "系统设置-用户和账户",
            with: "系统「设置」顶部的 Apple 账户"
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "icloud.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("云同步暂不可用")
                    .font(.title3.bold())

                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(hasLocalFavorites
                     ? "这台设备上的收藏仍可正常浏览和使用。"
                     : "这台设备还没有收藏。你仍可以浏览直播并添加收藏，内容会保存在本地。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if needsSignIn {
                    Button("查看登录方法") { showsSignInInstructions = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Button("已登录，重新检查", action: onRetry)
                        .frame(minHeight: 44)
                        .disabled(isRefreshing)
                } else {
                    Button("重新检查同步", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isRefreshing)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppConstants.Colors.primaryBackground)
        .alert("登录 iCloud", isPresented: $showsSignInInstructions) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("1. 打开这台设备的系统「设置」。\n2. 点击顶部的 Apple 账户入口，按提示登录。\n3. 返回 AngelLive，点击「已登录，重新检查」。\n\n如果已经登录，请在「设置」→ Apple 账户 → iCloud 中检查 AngelLive 的使用权限。")
        }
    }
}

#Preview {
    FavoriteView()
        .environment(AppFavoriteModel())
}
