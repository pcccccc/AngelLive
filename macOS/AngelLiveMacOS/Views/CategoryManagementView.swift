//
//  CategoryManagementView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/12/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import Kingfisher

/// 分类筛选面板:左侧竖排一级分类,右侧二级分类网格。
/// 两栏均为纵向滚动,鼠标滚轮原生可用,无需横向滚轮补丁。
struct CategoryManagementView: View {
    @Environment(PlatformDetailViewModel.self) private var viewModel
    /// 面板内正在浏览的一级分类(未提交),提交发生在点击二级分类时。
    @State private var browsingMainIndex = 0
    let onDismiss: () -> Void

    private let gridColumns = [GridItem(.adaptive(minimum: 96, maximum: 132), spacing: 12)]

    var body: some View {
        HStack(spacing: 0) {
            mainCategorySidebar
            Divider()
            subCategoryGrid
        }
        .macSettingsPage("选择分类")
        .onAppear {
            browsingMainIndex = viewModel.selectedMainCategoryIndex
        }
    }

    // MARK: - 左侧一级分类

    private var mainCategorySidebar: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(viewModel.categories.enumerated()), id: \.offset) { index, category in
                    MainCategoryRow(
                        title: category.title,
                        isSelected: browsingMainIndex == index
                    ) {
                        browsingMainIndex = index
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 150)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
    }

    // MARK: - 右侧二级分类网格

    @ViewBuilder
    private var subCategoryGrid: some View {
        if currentSubCategories.isEmpty {
            ContentUnavailableView("该分类下暂无子分类", systemImage: "square.grid.2x2")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(Array(currentSubCategories.enumerated()), id: \.offset) { index, subCategory in
                        Button { commit(subIndex: index) } label: {
                            CategoryCard(category: subCategory, isSelected: isCommitted(subIndex: index),
                                         platformIcon: platformIcon)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isCommitted(subIndex: index) ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 数据 / 逻辑

    private var currentSubCategories: [LiveCategoryModel] {
        guard viewModel.categories.indices.contains(browsingMainIndex) else { return [] }
        return viewModel.categories[browsingMainIndex].subList
    }

    /// 是否为当前已提交(生效中)的分类,用于高亮。
    private func isCommitted(subIndex: Int) -> Bool {
        browsingMainIndex == viewModel.selectedMainCategoryIndex
            && subIndex == viewModel.selectedSubCategoryIndex
    }

    /// 先关闭面板,再在后台切换分类——避免等网络请求返回才关窗的卡顿。
    private func commit(subIndex: Int) {
        let mainIndex = browsingMainIndex
        onDismiss()
        Task {
            await viewModel.selectCategory(mainIndex: mainIndex, subIndex: subIndex)
        }
    }

    /// 平台默认图标
    private var platformIcon: NSImage? {
        MacPlatformIconProvider.tabImage(for: viewModel.platform.liveType)
    }
}

// MARK: - 一级分类行

private struct MainCategoryRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? AppConstants.Colors.accent : .clear)
                    .frame(width: 3, height: 15)

                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .padding(.trailing, 6)
            .contentShape(Rectangle())
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return AppConstants.Colors.accent.opacity(0.14)
        }
        return isHovering ? Color.primary.opacity(0.06) : .clear
    }
}

// MARK: - 二级分类卡片

struct CategoryCard: View {
    let category: LiveCategoryModel
    let isSelected: Bool
    let platformIcon: NSImage?

    @State private var isHovering = false

    /// 分类图标 URL（如果有）
    private var categoryIconURL: URL? {
        guard !category.icon.isEmpty else { return nil }
        return URL(string: category.icon)
    }

    var body: some View {
        VStack(spacing: 8) {
            icon
                .frame(width: 44, height: 44)
                .padding(9)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

            Text(category.title)
                .font(.caption)
                .foregroundStyle(isSelected ? AppConstants.Colors.accent : Color.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? AppConstants.Colors.accent : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var icon: some View {
        if let iconURL = categoryIconURL {
            KFImage(iconURL)
                .placeholder { placeholderIcon }
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            placeholderIcon
        }
    }

    @ViewBuilder
    private var placeholderIcon: some View {
        if let platformIcon {
            Image(nsImage: platformIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private var cardBackground: Color {
        if isSelected {
            return AppConstants.Colors.accent.opacity(0.10)
        }
        return isHovering ? Color.primary.opacity(0.05) : .clear
    }
}
