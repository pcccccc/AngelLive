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

struct PlatformDetailView: View {
    @Environment(PlatformDetailViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if let error = viewModel.categoryError {
                ContentUnavailableView(
                    "加载失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isLoadingCategories && viewModel.categories.isEmpty {
                ProgressView("加载分类中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.categories.isEmpty {
                // 分类选择按钮
                categoryButton

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
        .task {
            if viewModel.categories.isEmpty {
                await viewModel.loadCategories()
            }
        }
    }

    // MARK: - 分类选择按钮
    private var categoryButton: some View {
        NavigationLink(destination: CategoryManagementView().environment(viewModel)) {
            HStack {
                Text(viewModel.currentCategoryTitle)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.down")
            }
            .padding()
        }
        .buttonStyle(.plain)
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
            ContentUnavailableView(
                "加载失败",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        GridItem(.adaptive(minimum: 220, maximum: 310), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(rooms) { room in
                        Button {
                            openWindow(value: room)
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
}

// MARK: - 直播间卡片
struct LiveRoomCard: View {
    let room: LiveModel

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
