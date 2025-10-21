//
//  PageView.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI

/// 支持滑动进度追踪的分页视图
struct PageView<Content: View>: View {
    let pageCount: Int
    @Binding var currentPage: Int
    @Binding var dragProgress: CGFloat
    @ViewBuilder let content: (Int) -> Content

    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @State private var pageWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    content(index)
                        .frame(width: geometry.size.width)
                }
            }
            .offset(x: -CGFloat(currentPage) * geometry.size.width + offset)
            .gesture(
                DragGesture(minimumDistance: 20)  // 增加最小距离，更容易区分方向
                    .onChanged { value in
                        // 判断滑动方向，只处理水平滑动
                        let horizontalAmount = abs(value.translation.width)
                        let verticalAmount = abs(value.translation.height)

                        // 如果是垂直滑动，不处理
                        if !isDragging && verticalAmount > horizontalAmount {
                            return
                        }

                        if !isDragging {
                            isDragging = true
                            pageWidth = geometry.size.width
                        }
                        offset = value.translation.width

                        // 计算当前拖动进度（使用缓存的 pageWidth）
                        if pageWidth > 0 {
                            let progress = CGFloat(currentPage) - (offset / pageWidth)
                            dragProgress = max(0, min(CGFloat(pageCount - 1), progress))
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        let threshold = pageWidth * 0.3
                        var newPage = currentPage

                        if value.translation.width < -threshold && currentPage < pageCount - 1 {
                            newPage += 1
                        } else if value.translation.width > threshold && currentPage > 0 {
                            newPage -= 1
                        }

                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            currentPage = newPage
                            offset = 0
                            dragProgress = CGFloat(newPage)
                        }
                    }
            )
        }
    }
}
