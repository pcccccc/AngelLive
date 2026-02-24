//
//  PlatformDetailView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import LiveParse
import Kingfisher
import Pow

struct PlatformDetailView: View {
    @Environment(PlatformDetailViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @State private var showCategorySheet = false
    @State private var isRefreshing = false
    @State private var showBilibiliLogin = false

    /// 当前分类图标 URL（如果有）
    private var categoryIconURL: URL? {
        guard let icon = viewModel.currentSubCategory?.icon, !icon.isEmpty else { return nil }
        return URL(string: icon)
    }

    /// 平台默认图标
    private var platformIcon: String {
        switch viewModel.platform.liveType {
        case .bilibili:
            return "mini_live_card_bili"
        case .douyu:
            return "mini_live_card_douyu"
        case .huya:
            return "mini_live_card_huya"
        case .douyin:
            return "mini_live_card_douyin"
        case .yy:
            return "mini_live_card_yy"
        case .cc:
            return "mini_live_card_cc"
        case .ks:
            return "mini_live_card_ks"
        case .soop:
            return "mini_live_card_soop"
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if let error = viewModel.categoryError {
                ErrorView(
                    title: error.isBilibiliAuthRequired ? "加载失败-请登录B站账号并检查官方页面" : "加载失败",
                    message: error.liveParseMessage,
                    detailMessage: error.liveParseDetail,
                    curlCommand: error.liveParseCurl,
                    showRetry: true,
                    showLoginButton: error.isBilibiliAuthRequired,
                    onRetry: {
                        Task {
                            await viewModel.loadCategories()
                        }
                    },
                    onLogin: error.isBilibiliAuthRequired ? {
                        showBilibiliLogin = true
                    } : nil
                )
            } else if viewModel.isLoadingCategories && viewModel.categories.isEmpty {
                ProgressView("加载分类中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.categories.isEmpty {
                // 房间列表
                roomListView
            } else {
                ContentUnavailableView(
                    "暂无分类",
                    systemImage: "list.bullet",
                    description: Text("当前平台没有可用的分类")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel.platform.title)
        .toolbar() {
            ToolbarItemGroup() {
                Button {
                    showCategorySheet.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if let iconURL = categoryIconURL {
                                KFImage(iconURL)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(platformIcon)
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                        .frame(width: 16, height: 16)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                        
                        Text(viewModel.currentCategoryTitle)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.vertical, 8)
                }
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }
            
            ToolbarItemGroup() {
                Button {
                    refreshContent()
                } label: {
                    Image(systemName: "arrow.trianglehead.2.counterclockwise")
                        .font(.body)
                        .frame(width: 16, height: 16)
                }
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isRefreshing
                )
                .disabled(isRefreshing || viewModel.isLoadingRooms)
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
            }
        }
        .overlay {
            if showCategorySheet {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCategorySheet = false
                            }
                        }

                    VStack(spacing: 12) {
                        HStack {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showCategorySheet = false
                                }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.title2)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.escape, modifiers: [])
                            .foregroundColor(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        CategoryManagementView(onDismiss: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showCategorySheet = false
                            }
                        })
                            .environment(viewModel)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                    }
                    .frame(width: 560, height: 460)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(radius: 20)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCategorySheet)
        .sheet(isPresented: $showBilibiliLogin) {
            BilibiliWebLoginView()
        }
        .task {
            if viewModel.categories.isEmpty {
                await viewModel.loadCategories()
            }
        }
    }

    // MARK: - 一级分类导航
    private var mainCategoryNavigator: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.categories.enumerated()), id: \.offset) { index, category in
                        Button(action: {
                            Task {
                                await viewModel.selectMainCategory(index: index)
                            }
                        }) {
                            Text(category.title)
                                .font(viewModel.selectedMainCategoryIndex == index ? .headline : .subheadline)
                                .fontWeight(viewModel.selectedMainCategoryIndex == index ? .bold : .regular)
                                .foregroundColor(viewModel.selectedMainCategoryIndex == index ? .white : .primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.selectedMainCategoryIndex == index ? Color.accentColor : Color.gray.opacity(0.2))
                                )
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: viewModel.selectedMainCategoryIndex) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 50)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 二级分类导航
    private var subCategoryNavigator: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.currentSubCategories.enumerated()), id: \.offset) { index, subCategory in
                        Button(action: {
                            Task {
                                await viewModel.selectSubCategory(index: index)
                            }
                        }) {
                            Text(subCategory.title)
                                .foregroundColor(viewModel.selectedSubCategoryIndex == index ? .accentColor : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: viewModel.selectedSubCategoryIndex) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 40)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - 房间列表视图
    @ViewBuilder
    private var roomListView: some View {
        let cacheKey = "\(viewModel.selectedMainCategoryIndex)-\(viewModel.selectedSubCategoryIndex)"
        let rooms = viewModel.roomListCache[cacheKey] ?? []

        if viewModel.isLoadingRooms && rooms.isEmpty {
            ProgressView("加载直播间...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.roomError, rooms.isEmpty {
            ErrorView(
                title: error.isBilibiliAuthRequired ? "加载失败-请登录B站账号并检查官方页面" : "加载失败",
                message: error.liveParseMessage,
                detailMessage: error.liveParseDetail,
                curlCommand: error.liveParseCurl,
                showRetry: true,
                showLoginButton: error.isBilibiliAuthRequired,
                onRetry: {
                    Task {
                        await viewModel.loadRoomList()
                    }
                },
                onLogin: error.isBilibiliAuthRequired ? {
                    showBilibiliLogin = true
                } : nil
            )
        } else if rooms.isEmpty {
            ContentUnavailableView(
                "暂无直播",
                systemImage: "video.slash",
                description: Text("当前分类下没有正在直播的房间")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(rooms) { room in
                        Button {
                            fullscreenPlayerManager.openRoom(room, openWindow: openWindow)
                        } label: {
                            LiveRoomCard(room: room)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // 分页加载
                            if room.roomId == rooms.last?.roomId {
                                Task {
                                    await viewModel.loadMore()
                                }
                            }
                        }
                    }

                    // 加载更多指示器
                    if viewModel.isLoadingRooms {
                        HStack {
                            ProgressView()
                            Text("加载更多...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
                .padding(16)
            }
            .refreshable {
                await viewModel.loadRoomList()
            }
        }
    }

    // MARK: - Helper Functions
    private func refreshContent() {
        guard !isRefreshing else { return }

        Task {
            isRefreshing = true
            await viewModel.loadRoomList()
            isRefreshing = false
        }
    }

}

// MARK: - 直播间卡片
struct LiveRoomCard: View {
    let room: LiveModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(ToastManager.self) private var toastManager
    @State private var showOfflineAlert = false
    @State private var isFavoriteLoading = false
    @State private var isFavoriteAnimating = false

    // 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { $0.roomId == room.roomId })
    }

    // 判断是否正在直播
    private var isLive: Bool {
        guard let liveState = room.liveState else { return true }
        return LiveState(rawValue: liveState) == .live
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图
            KFImage(URL(string: room.roomCover))
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .resizable()
                .blur(radius: 10)
                .overlay(
                    KFImage(URL(string: room.roomCover))
                        .placeholder {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                )
                .aspectRatio(16/9, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // 主播信息
            HStack(spacing: 8) {
                KFImage(URL(string: room.userHeadImg))
                    .placeholder {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.roomTitle)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(room.userName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .overlay {
            if isFavoriteLoading {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                    ProgressView()
                }
            }
        }
        .changeEffect(
            .spray(origin: UnitPoint(x: 0.5, y: 0.3)) {
                Image(systemName: isFavorited ? "heart.fill" : "heart.slash.fill")
                    .foregroundStyle(.red)
            }, value: isFavoriteAnimating
        )
        .contextMenu {
            favoriteContextMenu
        }
    }

    @ViewBuilder
    private var favoriteContextMenu: some View {
        if isFavorited {
            Button(role: .destructive) {
                Task {
                    await removeFavorite()
                }
            } label: {
                Label("取消收藏", systemImage: "heart.slash.fill")
            }
        } else {
            Button {
                Task {
                    await addFavorite()
                }
            } label: {
                Label("收藏", systemImage: "heart.fill")
            }
        }

        // TODO: 复制功能暂时注释，后续有好想法再开启
        // Divider()
        //
        // Button {
        //     // 复制房间标题
        //     NSPasteboard.general.clearContents()
        //     NSPasteboard.general.setString(room.roomTitle, forType: .string)
        //     showToastMessage(icon: "doc.on.doc.fill", message: "已复制房间标题")
        // } label: {
        //     Label("复制房间标题", systemImage: "doc.on.doc")
        // }
        //
        // Button {
        //     // 复制主播名称
        //     NSPasteboard.general.clearContents()
        //     NSPasteboard.general.setString(room.userName, forType: .string)
        //     showToastMessage(icon: "doc.on.doc.fill", message: "已复制主播名称")
        // } label: {
        //     Label("复制主播名称", systemImage: "person.fill")
        // }
    }

    @MainActor
    private func addFavorite() async {
        guard !isFavoriteLoading else { return }
        isFavoriteLoading = true
        defer { isFavoriteLoading = false }

        do {
            try await favoriteModel.addFavorite(room: room)
            isFavoriteAnimating.toggle()
            toastManager.show(icon: "heart.fill", message: "收藏成功", type: .success)
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            toastManager.show(icon: "xmark.circle.fill", message: "收藏失败：\(errorMessage)", type: .error)
            print("收藏失败: \(error)")
        }
    }

    @MainActor
    private func removeFavorite() async {
        guard !isFavoriteLoading else { return }
        isFavoriteLoading = true
        defer { isFavoriteLoading = false }

        do {
            try await favoriteModel.removeFavoriteRoom(room: room)
            isFavoriteAnimating.toggle()
            toastManager.show(icon: "heart.slash.fill", message: "已取消收藏", type: .info)
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            toastManager.show(icon: "xmark.circle.fill", message: "取消收藏失败：\(errorMessage)", type: .error)
            print("取消收藏失败: \(error)")
        }
    }
}

#Preview {
    PlatformDetailView()
        .environment(PlatformDetailViewModel(platform: Platformdescription(
            title: "测试平台",
            bigPic: "test",
            smallPic: "test",
            descripiton: "测试描述",
            liveType: .bilibili
        )))
}
