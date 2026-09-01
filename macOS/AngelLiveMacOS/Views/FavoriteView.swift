//
//  FavoriteView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct FavoriteView: View {
    @Environment(AppFavoriteModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @State private var isRefreshing = false
    @State private var rotationAngle: Double = 0
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var contentWidth: CGFloat = 900
    private static var lastLeaveTimestamp: Date?
    private static var hasPerformedInitialSync = false

    // 过滤后的房间列表
    private var filteredGroupedRoomList: [FavoriteLiveSectionModel] {
        guard !searchText.isEmpty else {
            return viewModel.groupedRoomList
        }

        let lowercasedSearch = searchText.lowercased()
        return viewModel.groupedRoomList.compactMap { section in
            let filteredRooms = section.roomList.filter { room in
                room.userName.lowercased().contains(lowercasedSearch) ||
                room.roomTitle.lowercased().contains(lowercasedSearch)
            }

            guard !filteredRooms.isEmpty else { return nil }

            var newSection = section
            newSection.roomList = filteredRooms
            return newSection
        }
    }

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                skeletonView()
            } else if viewModel.shouldShowBlockingCloudError {
                // 仅真错误(未登录/拉取失败)显示同步不可用。关同步时 cloudKitReady 也为 false,
                // 但那是正常的纯本地态,应继续展示本地收藏(与 iOS 一致)。
                cloudKitErrorView()
            } else if viewModel.roomList.isEmpty {
                emptyStateView()
            } else {
                favoriteContentView(containerWidth: contentWidth)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            // 滚动时可见高度会变化，这里只观察视口宽度，避免滚动触发网格重排。
            guard newWidth > 0, abs(newWidth - contentWidth) >= 1 else { return }
            contentWidth = newWidth
        }
        .onTapGesture {
            if isSearching {
                withAnimation(.spring(duration: 0.25)) {
                    isSearching = false
                    searchText = ""
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if viewModel.isFavoriteStatusRefreshing {
                syncBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isFavoriteStatusRefreshing)
        .navigationTitle("收藏")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // 刷新按钮
                Button(action: {
                    refreshContent()
                }) {
                    Image(systemName: "arrow.trianglehead.2.counterclockwise")
                        .font(.body)
                        .frame(width: 16, height: 16)
                }
                .rotationEffect(.degrees(rotationAngle))
                .disabled(isRefreshing || viewModel.isLoading)
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed)
            }

            ToolbarItemGroup(placement: .automatic) {
                // 搜索按钮/搜索框
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: isSearching ? nil : 16, height: 16)

                    if isSearching {
                        TextField("搜索主播名或房间标题", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 160)

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: isSearching ? nil : 36, height: 36)
                .padding(.horizontal, isSearching ? 8 : 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isSearching {
                        withAnimation(.spring(duration: 0.25)) {
                            isSearching = true
                        }
                    }
                }
                .animation(.spring(duration: 0.25), value: isSearching)
            }
        }
        .task {
            handleOnAppear()
        }
        .onDisappear {
            FavoriteView.lastLeaveTimestamp = Date()
        }
    }

    @ViewBuilder
    private func emptyStateView() -> some View {
        ErrorView.empty(
            title: "暂无收藏",
            message: "在其他页面添加您喜欢的直播间，这里会自动显示收藏内容。",
            symbolName: "star",
            tint: .secondary
        )
    }

    @ViewBuilder
    private func cloudKitErrorView() -> some View {
        ErrorView(
            title: "收藏同步不可用",
            message: viewModel.cloudKitStateString,
            showRetry: true,
            onRetry: {
                startFavoriteSync(force: true)
            }
        )
    }

    private func startFavoriteSync(force: Bool) {
        Task(priority: .background) {
            await loadFavorites(force: force)
        }
    }

    @MainActor
    private func loadFavorites(force: Bool = false) async {
        if force {
            await viewModel.syncWithActor()
        } else if viewModel.shouldSync() {
            await viewModel.syncWithActor()
        }
    }

    private func handleOnAppear() {
        if !FavoriteView.hasPerformedInitialSync {
            FavoriteView.hasPerformedInitialSync = true
            startFavoriteSync(force: true)
            return
        }

        guard shouldForceRefresh() else { return }

        startFavoriteSync(force: true)
        FavoriteView.lastLeaveTimestamp = Date()
    }

    private func shouldForceRefresh() -> Bool {
        guard let lastLeave = FavoriteView.lastLeaveTimestamp else {
            return false
        }
        return Date().timeIntervalSince(lastLeave) > 300
    }

    private func refreshContent() {
        guard !isRefreshing else { return }

        Task {
            isRefreshing = true
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            await viewModel.pullToRefresh()
            withAnimation {
                rotationAngle = 0
            }
            isRefreshing = false
        }
    }

    /// 顶部 loading 只跟随收藏状态刷新的前台阶段，完成后自动隐藏。
    private var syncBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在同步收藏…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.quaternary.opacity(0.5))
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func skeletonView() -> some View {
        LazyVStack(spacing: 20) {
            skeletonLiveSection()
        }
        .padding(.top)
        .padding(.bottom, 80)
        .shimmering()
    }

    @ViewBuilder
    private func skeletonLiveSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 24)
                .padding(.horizontal, 20)

            LiveRoomSkeletonGrid(count: 8)
        }
    }

    @ViewBuilder
    private func favoriteContentView(containerWidth: CGFloat) -> some View {
        let displayList = mergedSections(filteredGroupedRoomList)

        if displayList.isEmpty && !searchText.isEmpty {
            // 搜索无结果
            ErrorView.empty(
                title: "未找到相关主播",
                message: "试试其他关键词，或者清空搜索看看全部收藏内容。",
                symbolName: "magnifyingglass",
                tint: .secondary
            )
        } else {
            let layout = FavoriteGridLayout(containerWidth: containerWidth)
            let elements = layout.elements(for: displayList)

            // 只使用一个懒加载容器。每行高度由固定卡片宽度和 16:9 封面决定，
            // 避免嵌套 LazyVGrid 在滚动复用时反复估算 section 高度。
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(elements) { element in
                    favoriteElementView(element, layout: layout)
                }
            }
            .padding(.bottom, 80)
        }
    }

    /// `FavoriteLiveSectionModel.id` 就是逻辑分组键。同步和状态刷新交叉时如果
    /// 短暂产生了同 ID section，展示层先合并再分行，避免同一个“已下播”标题出现两次。
    /// 房间按 `LiveModel.id` 去重，保留首次出现的顺序。
    private func mergedSections(
        _ sections: [FavoriteLiveSectionModel]
    ) -> [FavoriteLiveSectionModel] {
        var merged: [FavoriteLiveSectionModel] = []
        var sectionIndexByID: [String: Int] = [:]
        var roomIDsBySectionID: [String: Set<String>] = [:]

        for section in sections {
            if let existingIndex = sectionIndexByID[section.id] {
                var seenRoomIDs = roomIDsBySectionID[section.id, default: []]
                let uniqueRooms = section.roomList.filter { room in
                    seenRoomIDs.insert(room.id).inserted
                }
                merged[existingIndex].roomList.append(contentsOf: uniqueRooms)
                roomIDsBySectionID[section.id] = seenRoomIDs
            } else {
                var seenRoomIDs = Set<String>()
                var uniqueSection = section
                uniqueSection.roomList = section.roomList.filter { room in
                    seenRoomIDs.insert(room.id).inserted
                }
                sectionIndexByID[section.id] = merged.count
                roomIDsBySectionID[section.id] = seenRoomIDs
                merged.append(uniqueSection)
            }
        }

        return merged
    }

    @ViewBuilder
    private func favoriteElementView(
        _ element: FavoriteGridElement,
        layout: FavoriteGridLayout
    ) -> some View {
        switch element {
        case let .header(title, count, isLive, isFirst):
            HStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLive ? Color.green.gradient : Color.gray.gradient)
                    .frame(width: 4, height: 18)

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(.quaternary.opacity(0.5))
                    )

                Spacer()
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.top, isFirst ? 16 : 32)
            .padding(.bottom, 16)

        case let .roomRow(_, _, rooms, isLastInSection):
            HStack(alignment: .top, spacing: layout.horizontalSpacing) {
                ForEach(rooms) { room in
                    LiveRoomCardButton(room: room) {
                        // 收藏页卡片不再观察整份收藏数组，减少任意房间更新造成的全屏重算。
                        LiveRoomCard(
                            room: room,
                            showsCoverBadge: true,
                            isFavoritedOverride: true
                        )
                        .frame(width: layout.cardWidth, alignment: .leading)
                    }
                    .frame(width: layout.cardWidth)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, isLastInSection ? 0 : layout.verticalSpacing)
        }
    }
}

private struct FavoriteGridLayout {
    let horizontalPadding: CGFloat
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let cardWidth: CGFloat
    let columnCount: Int

    init(containerWidth: CGFloat) {
        let horizontalPadding: CGFloat = 20
        let horizontalSpacing: CGFloat = 15
        let minimumCardWidth: CGFloat = 180
        let maximumCardWidth: CGFloat = 260
        let availableWidth = max(containerWidth - horizontalPadding * 2, minimumCardWidth)
        let columnsNeededForMaximumWidth = max(
            1,
            Int(ceil((availableWidth + horizontalSpacing) / (maximumCardWidth + horizontalSpacing)))
        )
        let columnsAllowedByMinimumWidth = max(
            1,
            Int(floor((availableWidth + horizontalSpacing) / (minimumCardWidth + horizontalSpacing)))
        )
        let columnCount = min(columnsNeededForMaximumWidth, columnsAllowedByMinimumWidth)

        self.horizontalPadding = horizontalPadding
        self.horizontalSpacing = horizontalSpacing
        verticalSpacing = 24
        self.columnCount = columnCount
        cardWidth = max(
            minimumCardWidth,
            min(
                maximumCardWidth,
                (availableWidth - horizontalSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
            )
        )
    }

    func elements(for sections: [FavoriteLiveSectionModel]) -> [FavoriteGridElement] {
        var result: [FavoriteGridElement] = []

        for (sectionIndex, section) in sections.enumerated() {
            result.append(
                .header(
                    title: section.title,
                    count: section.roomList.count,
                    isLive: section.title == "正在直播",
                    isFirst: sectionIndex == sections.startIndex
                )
            )

            let rowCount = Int(ceil(Double(section.roomList.count) / Double(columnCount)))
            for rowIndex in 0..<rowCount {
                let startIndex = rowIndex * columnCount
                let endIndex = min(startIndex + columnCount, section.roomList.count)
                result.append(
                    .roomRow(
                        sectionID: section.id,
                        rowIndex: rowIndex,
                        rooms: Array(section.roomList[startIndex..<endIndex]),
                        isLastInSection: rowIndex == rowCount - 1
                    )
                )
            }
        }

        return result
    }
}

private enum FavoriteGridElement: Identifiable {
    case header(title: String, count: Int, isLive: Bool, isFirst: Bool)
    case roomRow(
        sectionID: String,
        rowIndex: Int,
        rooms: [LiveModel],
        isLastInSection: Bool
    )

    var id: String {
        switch self {
        case let .header(title, _, _, _):
            return "header::\(title)"
        case let .roomRow(sectionID, rowIndex, _, _):
            return "row::\(sectionID)::\(rowIndex)"
        }
    }
}

#Preview {
    FavoriteView()
        .environment(AppFavoriteModel())
}
