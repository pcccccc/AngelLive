//
//  SegmentedControl.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI

/// 类似 JXSegmentedView 的分段控制器组件
struct SegmentedControl: View {
    let items: [String]
    @Binding var selectedIndex: Int
    @Namespace private var animation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items.indices, id: \.self) { index in
                        segmentButton(for: index)
                            .id(index)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(
                                        x: phase.isIdentity ? 1.0 : 0.95,
                                        y: phase.isIdentity ? 1.0 : 0.95
                                    )
                                    .opacity(phase.isIdentity ? 1.0 : 0.7)
                            }
                    }
                }
                .padding(.horizontal, AppConstants.Spacing.lg)
                .padding(.vertical, AppConstants.Spacing.sm)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .background(AppConstants.Colors.secondaryBackground)
            .onChange(of: selectedIndex) { oldValue, newValue in
                // 自动滚动到选中项
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentButton(for index: Int) -> some View {
        let isSelected = selectedIndex == index

        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedIndex = index
            }
        }) {
            VStack(spacing: 6) {
                Text(items[index])
                    .font(.system(size: isSelected ? 18 : 15))
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundStyle(isSelected ? AppConstants.Colors.primaryText : AppConstants.Colors.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectedIndex)

                // 指示器
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(AppConstants.Colors.accent)
                            .frame(height: 3)
                            .matchedGeometryEffect(id: "indicator", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .frame(height: 3)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var selectedIndex = 0

    VStack {
        SegmentedControl(
            items: ["推荐", "网游", "手游", "娱乐", "电台", "单机"],
            selectedIndex: $selectedIndex
        )

        Text("Selected: \(selectedIndex)")
            .padding()

        Spacer()
    }
}
