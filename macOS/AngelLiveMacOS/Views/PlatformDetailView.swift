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
    @State private var selectedMainCategory = 0
    @State private var selectedSubCategory = 0

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
            } else if viewModel.categories.isEmpty && viewModel.isLoadingCategories {
                ProgressView("加载分类中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.categories.isEmpty {
                // 分类导航
                VStack(spacing: 0) {
                    // 一级分类
                    if viewModel.categories.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(viewModel.categories.enumerated()), id: \.offset) { index, category in
                                    Button(action: {
                                        viewModel.selectedMainCategoryIndex = index
                                        viewModel.selectedSubCategoryIndex = 0
                                        Task {
                                            await viewModel.loadRoomList()
                                        }
                                    }) {
                                        Text(category.title)
                                            .font(.headline)
                                            .foregroundColor(viewModel.selectedMainCategoryIndex == index ? .white : .primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                viewModel.selectedMainCategoryIndex == index ?
                                                    Color.accentColor : Color.gray.opacity(0.2)
                                            )
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        Divider()
                    }

                    // 二级分类
                    if !viewModel.currentSubCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(viewModel.currentSubCategories.enumerated()), id: \.offset) { index, subCategory in
                                    Button(action: {
                                        viewModel.selectedSubCategoryIndex = index
                                        Task {
                                            await viewModel.loadRoomList()
                                        }
                                    }) {
                                        Text(subCategory.title)
                                            .foregroundColor(viewModel.selectedSubCategoryIndex == index ? .accentColor : .secondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        Divider()
                    }
                }

                // 房间列表
                roomListView
            }
        }
        .navigationTitle(viewModel.platform.title)
        .task {
            await viewModel.loadCategories()
        }
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
                        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
                    ],
                    spacing: 16
                ) {
                    ForEach(rooms) { room in
                        NavigationLink(value: room) {
                            LiveRoomCard(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - 直播间卡片
struct LiveRoomCard: View {
    let room: LiveModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 封面图
            KFImage(URL(string: room.roomCover))
                .placeholder {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
                .frame(height: 160)
                .clipped()
                .overlay(alignment: .topLeading) {
                    // 在线人数
                    if let count = room.liveWatchedCount, !count.isEmpty {
                        Text(count)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .padding(8)
                    }
                }

            // 房间信息
            VStack(alignment: .leading, spacing: 6) {
                Text(room.roomTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    // 主播头像
                    KFImage(URL(string: room.userHeadImg))
                        .placeholder {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())

                    Text(room.userName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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
