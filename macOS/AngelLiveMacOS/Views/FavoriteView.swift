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
import LiveParse

struct FavoriteView: View {
    @Environment(AppFavoriteModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @State private var isRefreshing = false
    @State private var rotationAngle: Double = 0
    @State private var searchText = ""
    @State private var isSearching = false
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
        GeometryReader { geometry in
            ScrollView {
                if viewModel.isLoading {
                    skeletonView(geometry: geometry)
                } else if viewModel.cloudKitReady {
                    if viewModel.roomList.isEmpty {
                        emptyStateView()
                    } else {
                        favoriteContentView(geometry: geometry)
                    }
                } else {
                    cloudKitErrorView()
                }
            }
            .onTapGesture {
                if isSearching {
                    withAnimation(.spring(duration: 0.25)) {
                        isSearching = false
                        searchText = ""
                    }
                }
            }
        }
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
        VStack(spacing: 20) {
            Image(systemName: "star.slash")
                .font(.system(size: 60))
                .foregroundStyle(.gray.opacity(0.5))

            Text("暂无收藏")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("在其他页面添加您喜欢的直播间")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    @ViewBuilder
    private func cloudKitErrorView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 60))
                .foregroundStyle(.red.opacity(0.7))

            Text(viewModel.cloudKitStateString)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button(action: {
                startFavoriteSync(force: true)
            }) {
                Label("重试", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @ViewBuilder
    private func skeletonView(geometry: GeometryProxy) -> some View {
        LazyVStack(spacing: 20) {
            skeletonLiveSection(geometry: geometry)
        }
        .padding(.top)
        .padding(.bottom, 80)
        .shimmering()
    }

    @ViewBuilder
    private func skeletonLiveSection(geometry: GeometryProxy) -> some View {
        let columns = 3
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20
        let screenWidth = geometry.size.width

        let totalHorizontalSpacing = horizontalPadding * 2 + horizontalSpacing * CGFloat(columns - 1)
        let cardWidth = (screenWidth - totalHorizontalSpacing) / CGFloat(columns)

        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 120, height: 24)
                .padding(.horizontal)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: horizontalSpacing), count: columns),
                spacing: verticalSpacing
            ) {
                ForEach(0..<columns, id: \.self) { _ in
                    LiveRoomCardSkeleton(width: cardWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private func favoriteContentView(geometry: GeometryProxy) -> some View {
        let displayList = filteredGroupedRoomList

        if displayList.isEmpty && !searchText.isEmpty {
            // 搜索无结果
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundStyle(.gray.opacity(0.5))

                Text("未找到相关主播")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text("请尝试其他关键词")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 100)
        } else {
            LazyVStack(spacing: 32) {
                ForEach(displayList, id: \.id) { section in
                    sectionView(section: section, geometry: geometry)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionView(section: FavoriteLiveSectionModel, geometry: GeometryProxy) -> some View {
        let isLiveSection = section.title == "正在直播"
        let screenWidth = geometry.size.width

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLiveSection ? Color.green.gradient : Color.gray.gradient)
                    .frame(width: 4, height: 18)

                Text(section.title)
                    .font(.title2.bold())
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Text("\(section.roomList.count)")
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
            .padding(.horizontal)

            liveSectionGrid(roomList: section.roomList, screenWidth: screenWidth)
        }
    }

    @ViewBuilder
    private func liveSectionGrid(roomList: [LiveModel], screenWidth: CGFloat) -> some View {
        let horizontalSpacing: CGFloat = 15
        let verticalSpacing: CGFloat = 24
        let horizontalPadding: CGFloat = 20

        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 180, maximum: 260), spacing: horizontalSpacing)
            ],
            spacing: verticalSpacing
        ) {
            ForEach(roomList, id: \.roomId) { room in
                LiveRoomCardButton(room: room) {
                    LiveRoomCard(room: room)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
    }
}

#Preview {
    FavoriteView()
        .environment(AppFavoriteModel())
}
