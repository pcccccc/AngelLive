//
//  SidebarView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/12/10.
//

import SwiftUI
import AngelLiveDependencies

struct SidebarView: View {

    @Environment(LiveViewModel.self) var liveViewModel
    @FocusState.Binding var focusState: FocusableField?

    var body: some View {
        HStack(spacing: 0) {
            if liveViewModel.isSidebarExpanded {
                mainSidebarContent
                    .frame(width: liveViewModel.sidebarPeekWidth + liveViewModel.sidebarWidth)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if !liveViewModel.isSidebarExpanded {
                edgeIndicator
                    .frame(width: liveViewModel.sidebarPeekWidth)
                    .clipped()
                    .ignoresSafeArea()
            }
            
            Spacer()
        }
        
        .frame(width: liveViewModel.sidebarPeekWidth + liveViewModel.sidebarWidth)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: liveViewModel.isSidebarExpanded)
        .onExitCommand {
            handleExitCommand()
        }

    }

    private func handleExitCommand() {
        guard liveViewModel.isSidebarExpanded else { return }

        switch focusState {
        case .leftMenu(let parentIndex, let subIndex):
            if subIndex > 0 {
                // 子菜单项 -> 返回到主菜单项
                focusState = .leftMenu(parentIndex, 0)
            } else {
                // 主菜单项 -> 关闭 sidebar
                liveViewModel.isSidebarExpanded = false
                focusState = .mainContent(max(0, liveViewModel.selectedRoomListIndex))
            }
        default:
            // 其他情况关闭 sidebar
            liveViewModel.isSidebarExpanded = false
            focusState = .mainContent(max(0, liveViewModel.selectedRoomListIndex))
        }
    }

    // MARK: - 主 Sidebar 内容
    private var mainSidebarContent: some View {
        ScrollView {
            VStack(alignment: .center) {
                Text("分类")
                    .font(.title3)
                    .bold()
                    .padding(.top, 20)

                ForEach(liveViewModel.categories.indices, id: \.self) { index in
                    SidebarMenuItem(
                        focusState: $focusState,
                        icon: liveViewModel.categories[index].icon.isEmpty ? liveViewModel.menuTitleIcon : liveViewModel.categories[index].icon,
                        title: liveViewModel.categories[index].title,
                        index: index,
                        subItems: liveViewModel.categories[index].subList
                    )
                    .environment(liveViewModel)
                    .padding(.top, index == 0 ? 20 : 0)
                    .padding(.bottom, index == liveViewModel.categories.count - 1 ? 50 : 0)
                    .padding(.trailing, 45)
                }
            }
        }
        .frame(minHeight: 30, maxHeight: .infinity, alignment: .top)
        .background(.thinMaterial)
    }

    // MARK: - 右侧指示器
    private var edgeIndicator: some View {
        VStack(spacing: 8) {
            // 当前分类图标
            currentCategoryIcon
                .frame(width: 24, height: 24)
                .cornerRadius(12)

            // 展开箭头
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(width: liveViewModel.sidebarPeekWidth, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.15))
        )
        .frame(maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var currentCategoryIcon: some View {
        let icon = currentSelectedIcon
        if icon.isEmpty || icon == liveViewModel.menuTitleIcon {
            Image(liveViewModel.menuTitleIcon)
                .resizable()
                .scaledToFit()
        } else {
            KFImage(URL(string: icon))
                .placeholder {
                    Image(liveViewModel.menuTitleIcon)
                        .resizable()
                        .scaledToFit()
                }
                .resizable()
                .scaledToFit()
        }
    }

    private var currentSelectedIcon: String {
        if liveViewModel.selectedSubCategory.count > 0,
           liveViewModel.selectedSubListIndex >= 0,
           liveViewModel.selectedSubListIndex < liveViewModel.selectedSubCategory.count {
            return liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].icon
        } else if let firstCategory = liveViewModel.categories.first,
                  let firstSubCategory = firstCategory.subList.first {
            return firstSubCategory.icon
        }
        return ""
    }
}

// MARK: - Sidebar 菜单项
struct SidebarMenuItem: View {

    @Environment(LiveViewModel.self) var liveViewModel
    @FocusState.Binding var focusState: FocusableField?
    var icon: String
    var title: String
    var index: Int
    var subItems: [LiveCategoryModel]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 主分类按钮
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 14) {
                    // 图标
                    if icon.hasPrefix("http") {
                        KFImage(URL(string: icon))
                            .resizable()
                            .frame(width: 40, height: 40)
                            .cornerRadius(20)
                    } else {
                        Image(icon)
                            .resizable()
                            .frame(width: 40, height: 40)
                            .cornerRadius(20)
                    }

                    Text(title)
                        .font(.system(size: 28))
                        .lineLimit(1)
                        .layoutPriority(1)
                        .frame(minWidth: 28 * 5, alignment: .leading)


                    Spacer()

                    // 展开箭头
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.card)
            .focused($focusState, equals: .leftMenu(index, 0))

            // 子分类列表
            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(subItems.enumerated()), id: \.element.id) { subIndex, item in
                        SidebarSubMenuItem(
                            focusState: $focusState,
                            icon: item.icon.isEmpty ? liveViewModel.menuTitleIcon : item.icon,
                            title: item.title,
                            subIndex: subIndex,
                            parentIndex: index
                        )
                        .environment(liveViewModel)
                    }
                }
                .padding(.leading, 10)
                .padding(.top, 28)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }
}

// MARK: - Sidebar 子菜单项
struct SidebarSubMenuItem: View {

    @Environment(LiveViewModel.self) var liveViewModel
    @FocusState.Binding var focusState: FocusableField?
    var icon: String
    var title: String
    var subIndex: Int
    var parentIndex: Int

    private var isSelected: Bool {
        liveViewModel.selectedSubListIndex == subIndex &&
        liveViewModel.selectedMainListCategory?.title == liveViewModel.categories[safe: parentIndex]?.title
    }

    var body: some View {
        Button {
            selectSubCategory()
        } label: {
            HStack(spacing: 12) {
                // 选中指示条
                RoundedRectangle(cornerRadius: 3)
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 30)

                // 图标
                if icon == "douyin" || !icon.hasPrefix("http") {
                    Image(icon.isEmpty ? "placeholder" : icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(16)
                } else {
                    KFImage(URL(string: icon))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(16)
                }

                Text(title)
                    .font(.system(size: 24, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.card)
        .focused($focusState, equals: .leftMenu(parentIndex, subIndex + 1))
    }

    private func selectSubCategory() {
        // 设置选中的主分类
        if parentIndex < liveViewModel.categories.count {
            liveViewModel.selectedMainListCategory = liveViewModel.categories[parentIndex]
        }
        liveViewModel.selectedSubListIndex = subIndex
        liveViewModel.roomPage = 1
        liveViewModel.getRoomList(index: subIndex)
        // 选择后收起 sidebar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            liveViewModel.isSidebarExpanded = false
            focusState = .mainContent(0)
        }
    }
}

// MARK: - 安全数组访问扩展
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
