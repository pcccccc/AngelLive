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

struct CategoryManagementView: View {
    @Environment(PlatformDetailViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMainIndex = 0

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(Array(viewModel.categories.enumerated()), id: \.offset) { index, category in
                        VStack(spacing: 4) {
                            Text(category.title)
                                .font(.system(size: 14, weight: selectedMainIndex == index ? .semibold : .regular))
                                .foregroundColor(selectedMainIndex == index ? .primary : .secondary)

                            Capsule()
                                .fill(selectedMainIndex == index ? Color.accentColor : Color.clear)
                                .frame(width: 20, height: 3)
                        }
                        .onTapGesture {
                            selectedMainIndex = index
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 16)], spacing: 16) {
                    ForEach(Array(currentSubCategories.enumerated()), id: \.offset) { index, subCategory in
                        CategoryCard(category: subCategory, isSelected: isSelected(mainIndex: selectedMainIndex, subIndex: index))
                            .onTapGesture {
                                Task {
                                    await viewModel.selectMainCategory(index: selectedMainIndex)
                                    await viewModel.selectSubCategory(index: index)
                                    dismiss()
                                }
                            }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("全部分类")
        .onAppear {
            selectedMainIndex = viewModel.selectedMainCategoryIndex
        }
    }

    private var currentSubCategories: [LiveCategoryModel] {
        guard viewModel.categories.indices.contains(selectedMainIndex) else { return [] }
        return viewModel.categories[selectedMainIndex].subList
    }

    private func isSelected(mainIndex: Int, subIndex: Int) -> Bool {
        mainIndex == viewModel.selectedMainCategoryIndex && subIndex == viewModel.selectedSubCategoryIndex
    }
}

struct CategoryCard: View {
    let category: LiveCategoryModel
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            KFImage(URL(string: category.icon))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

            Text(category.title)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .frame(width: 80, height: 80)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .cornerRadius(8)
    }
}
