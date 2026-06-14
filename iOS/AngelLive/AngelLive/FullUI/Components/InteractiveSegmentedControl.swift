//
//  InteractiveSegmentedControl.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI
import AngelLiveCore

/// 支持跟手动画的分段控制器
struct InteractiveSegmentedControl: View {
    let items: [String]
    @Binding var selectedIndex: Int
    @Binding var dragProgress: CGFloat  // 拖动进度 (0.0 到页面数)

    // 缓存颜色组件，避免重复计算
    private let secondaryTextComponents: (red: CGFloat, green: CGFloat, blue: CGFloat)
    private let primaryTextComponents: (red: CGFloat, green: CGFloat, blue: CGFloat)

    init(items: [String], selectedIndex: Binding<Int>, dragProgress: Binding<CGFloat>) {
        self.items = items
        self._selectedIndex = selectedIndex
        self._dragProgress = dragProgress

        // 初始化时计算颜色组件
        self.secondaryTextComponents = Self.colorComponents(AppConstants.Colors.secondaryText)
        self.primaryTextComponents = Self.colorComponents(AppConstants.Colors.primaryText)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items.indices, id: \.self) { index in
                        segmentButton(for: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.lg)
                .padding(.vertical, AppConstants.Spacing.sm)
            }
            .background(AppConstants.Colors.secondaryBackground)
            .onChange(of: selectedIndex) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentButton(for index: Int) -> some View {
        let animationProgress = calculateAnimationProgress(for: index)

        Button(action: {
            Logger.debug("🔘 点击了分类按钮，index: \(index), 当前 selectedIndex: \(selectedIndex)", category: .ui)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedIndex = index
                dragProgress = CGFloat(index)  // 同步更新 dragProgress
            }
            Logger.debug("🔘 设置后 selectedIndex: \(selectedIndex), dragProgress: \(dragProgress)", category: .ui)
        }) {
            VStack(spacing: 6) {
                Text(items[index])
                    .font(.system(size: fontSize(progress: animationProgress)))
                    .fontWeight(fontWeight(progress: animationProgress))
                    .foregroundStyle(textColor(progress: animationProgress))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                // 简化指示器：每个分段都有自己的指示器，通过透明度和宽度变化
                indicator(for: index, progress: animationProgress)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func indicator(for index: Int, progress: CGFloat) -> some View {
        // 宽度固定为40pt
        Capsule()
            .fill(AppConstants.Colors.accent)
            .frame(width: 40, height: 3)
            .opacity(progress)  // 透明度根据进度变化
    }

    // MARK: - 动画计算

    /// 计算基于拖动进度的动画进度
    private func calculateAnimationProgress(for index: Int) -> CGFloat {
        let currentPage = dragProgress
        let pageInt = Int(round(currentPage))
        let offset = currentPage - CGFloat(pageInt)

        if index == pageInt {
            // 当前页正在离开
            return max(0, 1.0 - abs(offset))
        } else if offset > 0 && index == pageInt + 1 {
            // 向右滑：下一页正在进入
            return min(1.0, offset)
        } else if offset < 0 && index == pageInt - 1 {
            // 向左滑：上一页正在进入
            return min(1.0, -offset)
        }
        return 0.0
    }

    private func fontSize(progress: CGFloat) -> CGFloat {
        15 + (18 - 15) * progress
    }

    private func fontWeight(progress: CGFloat) -> Font.Weight {
        progress > 0.5 ? .bold : (progress > 0.2 ? .semibold : .regular)
    }

    private func textColor(progress: CGFloat) -> Color {
        return Color(
            red: interpolate(from: secondaryTextComponents.red, to: primaryTextComponents.red, progress: progress),
            green: interpolate(from: secondaryTextComponents.green, to: primaryTextComponents.green, progress: progress),
            blue: interpolate(from: secondaryTextComponents.blue, to: primaryTextComponents.blue, progress: progress)
        )
    }

    private func interpolate(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private static func colorComponents(_ color: Color) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue)
    }
}
