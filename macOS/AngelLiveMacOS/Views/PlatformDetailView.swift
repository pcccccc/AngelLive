//
//  PlatformDetailView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import Kingfisher
import Pow

struct PlatformDetailView: View {
    @Environment(PlatformDetailViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(FullscreenPlayerManager.self) private var fullscreenPlayerManager
    @State private var showCategorySheet = false
    @State private var isRefreshing = false
    @State private var showCapabilityPopover = false

    /// 根据平台类型生成登录相关的错误标题
    private var authErrorTitle: String {
        let platformName = LiveParseTools.getLivePlatformName(viewModel.platform.liveType)
        return "加载失败-请登录\(platformName)账号"
    }

    /// 当前分类图标 URL（如果有）
    private var categoryIconURL: URL? {
        guard let icon = viewModel.currentSubCategory?.icon, !icon.isEmpty else { return nil }
        return URL(string: icon)
    }

    /// 平台默认图标
    private var platformIcon: NSImage? {
        MacPlatformIconProvider.tabImage(for: viewModel.platform.liveType)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if let error = viewModel.categoryError {
                ErrorView(
                    title: error.isAuthRequired ? authErrorTitle : "加载失败",
                    message: error.liveParseMessage,
                    detailMessage: error.liveParseDetail,
                    curlCommand: error.liveParseCurl,
                    showRetry: true,
                    showLoginButton: error.isAuthRequired,
                    onRetry: {
                        Task {
                            await viewModel.loadCategories()
                        }
                    },
                    onLogin: error.isAuthRequired ? {
                        NotificationCenter.default.post(name: .switchToSettings, object: nil)
                    } : nil
                )
            } else if viewModel.isLoadingCategories && viewModel.categories.isEmpty {
                ProgressView("加载分类中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.categories.isEmpty {
                // 房间列表
                roomListView
            } else {
                ErrorView.empty(
                    title: "暂无分类",
                    message: "当前页面还没有可用分类，请稍后再试。",
                    symbolName: "list.bullet.rectangle",
                    tint: .secondary
                )
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
                                    .placeholder {
                                        if let platformIcon {
                                            Image(nsImage: platformIcon)
                                                .resizable()
                                                .scaledToFit()
                                        } else {
                                            Image(systemName: "puzzlepiece.extension")
                                                .resizable()
                                                .scaledToFit()
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .resizable()
                                    .scaledToFit()
                            } else if let platformIcon {
                                Image(nsImage: platformIcon)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "puzzlepiece.extension")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
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
                    showCapabilityPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .frame(width: 16, height: 16)
                }
                .popover(isPresented: $showCapabilityPopover) {
                    PlatformCapabilityPopover(liveType: viewModel.platform.liveType)
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)

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
            .enableMacHorizontalWheelScroll()
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
            .enableMacHorizontalWheelScroll()
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
                title: error.isAuthRequired ? authErrorTitle : "加载失败",
                message: error.liveParseMessage,
                detailMessage: error.liveParseDetail,
                curlCommand: error.liveParseCurl,
                showRetry: true,
                showLoginButton: error.isAuthRequired,
                onRetry: {
                    Task {
                        await viewModel.loadRoomList()
                    }
                },
                onLogin: error.isAuthRequired ? {
                    NotificationCenter.default.post(name: .switchToSettings, object: nil)
                } : nil
            )
        } else if rooms.isEmpty {
            ErrorView.empty(
                title: "暂无直播",
                message: "当前分类下没有正在直播的房间。",
                symbolName: "video.slash",
                tint: .secondary
            )
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
                    } else if !viewModel.hasMoreRooms && !rooms.isEmpty {
                        Text("已经到底了")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
    let showsCoverBadge: Bool

    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(ToastManager.self) private var toastManager
    @State private var isFavoriteLoading = false
    @State private var isFavoriteAnimating = false

    init(room: LiveModel, showsCoverBadge: Bool = false) {
        self.room = room
        self.showsCoverBadge = showsCoverBadge
    }

    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { $0.roomId == room.roomId })
    }

    // TODO: 平台图标和直播状态暂时隐藏，待重新设计后恢复
//    private var badgeLiveState: LiveState {
//        guard let liveState = room.liveState, let state = LiveState(rawValue: liveState) else {
//            return .live
//        }
//        return state
//    }

    private var coverURL: URL? {
        guard !room.roomCover.isEmpty, let url = URL(string: room.roomCover) else { return nil }
        return url
    }

//    private var liveStatusText: String {
//        switch badgeLiveState {
//        case .live:
//            return "直播中"
//        case .close:
//            return "已下播"
//        case .video:
//            return "回放中"
//        case .unknow:
//            return "待确认"
//        }
//    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            coverView
                // TODO: 平台图标和直播状态暂时隐藏，待重新设计后恢复
//                .overlay(alignment: .topTrailing) {
//                    if showsCoverBadge {
//                        coverInfoBadge
//                            .padding(6)
//                    }
//                }
                .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg))

            HStack(spacing: 8) {
                RemoteAvatarView(url: URL(string: room.userHeadImg), size: 32) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(4)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.roomTitle.orDash)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(room.userName.orDash)
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

    private var coverView: some View {
        Group {
            if let coverURL {
                KFImage(coverURL)
                    .placeholder {
                        placeholderCover()
                    }
                    .resizable()
                    .blur(radius: 20)
                    .overlay(
                        KFImage(coverURL)
                            .placeholder {
                                placeholderCover()
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    )
            } else {
                placeholderCover()
            }
        }
        .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
    }

    private func placeholderCover() -> some View {
        ZStack {
            Rectangle()
                .fill(AppConstants.Colors.placeholderGradient())
            Image("placeholder")
                .resizable()
                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                .opacity(0.7)
        }
        .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
    }

//    private var coverInfoBadge: some View {
//        HStack(spacing: 6) {
//            platformBadgeIcon
//
//            Text(liveStatusText)
//                .font(.caption2.weight(.medium))
//                .foregroundStyle(.white)
//                .lineLimit(1)
//        }
//        .padding(.horizontal, 7)
//        .padding(.vertical, 4)
//        .background(
//            Capsule(style: .continuous)
//                .fill(Color.black.opacity(0.58))
//        )
//        .overlay(
//            Capsule(style: .continuous)
//                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
//        )
//        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
//    }
//
//    @ViewBuilder
//    private var platformBadgeIcon: some View {
//        if let image = MacPlatformIconProvider.tabImage(for: room.liveType) {
//            Image(nsImage: image)
//                .resizable()
//                .scaledToFit()
//                .frame(width: 12, height: 12)
//                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
//        } else {
//            Image(systemName: "dot.radiowaves.left.and.right")
//                .font(.caption2.weight(.bold))
//                .foregroundStyle(.white.opacity(0.92))
//                .frame(width: 12, height: 12)
//        }
//    }

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
            Logger.warning("收藏失败: \(error)", category: .favorite)
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
            Logger.warning("取消收藏失败: \(error)", category: .favorite)
        }
    }
}

#Preview {
    PlatformDetailView()
        .environment(PlatformDetailViewModel(platform: Platformdescription(
            title: "测试平台",
            pluginId: "preview",
            bigPic: "test",
            smallPic: "test",
            descripiton: "测试描述",
            liveType: .placeholder
        )))
}
