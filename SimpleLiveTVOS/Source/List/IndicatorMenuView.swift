//
//  IndicatorMenuView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/12.
//

import SwiftUI
import Kingfisher
import ColorfulX

struct IndicatorMenuView: View {
    
    @Environment(LiveViewModel.self) var liveViewModel
    @State var colors: [Color] = ColorfulPreset.autumn.colors
    
    var body: some View {
        HStack {
            if shouldShowCategory {
                categoryContent
            } else {
                defaultCategoryContent
            }
        }
        .frame(width: liveViewModel.leftWidth, height: liveViewModel.leftHeight)
        .background(ColorfulView(color: $colors)
            .ignoresSafeArea())
        .cornerRadius(liveViewModel.leftMenuCornerRadius)
        .offset(x: 60, y: 70)
        .opacity(liveViewModel.showOverlay ? 0 : 1)
    }

    private var shouldShowCategory: Bool {
        liveViewModel.selectedSubCategory.count > 0 && liveViewModel.selectedSubListIndex != -1
    }

    private var categoryContent: some View {
        HStack(spacing: 10) {
            iconView(liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].icon)
            textView(liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].title)
        }
    }

    private var defaultCategoryContent: some View {
        HStack(spacing: 10) {
            iconView(liveViewModel.categories.first?.subList.first?.icon ?? "")
            textView(liveViewModel.categories.first?.subList.first?.title ?? "")
        }
    }

    private func iconView(_ icon: String) -> some View {
        Group {
            if icon.isEmpty {
                Image(liveViewModel.menuTitleIcon)
                    .resizable()
            } else {
                KFImage(URL(string: icon))
                    .placeholder {
                        Image(liveViewModel.menuTitleIcon)
                            .resizable()
                    }
                    .resizable()
            }
        }
        .frame(width: 30, height: 30, alignment: .leading)
        .cornerRadius(15)
        .padding(.leading, -5)
    }

    private func textView(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20))
            .frame(width: 110, height: 30, alignment: .leading)
            .multilineTextAlignment(.leading)
            .foregroundColor(.white)
    }
}
