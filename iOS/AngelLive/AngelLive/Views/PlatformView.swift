//
//  PlatformView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore
import LiveParse

struct PlatformView: View {
    @Environment(PlatformViewModel.self) private var viewModel
    @Environment(SearchViewModel.self) private var searchViewModel
    @State private var navigationPath: [Platformdescription] = []
    @State private var showCapabilitySheet = false
    private let gridSpacing = AppConstants.Spacing.lg

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                let metrics = layoutMetrics(for: proxy.size)

                ScrollView {
                    LazyVGrid(
                        columns: metrics.columns,
                        spacing: gridSpacing
                    ) {
                        ForEach(viewModel.platformInfo) { platform in
                            platformNavigationItem(platform: platform, metrics: metrics)
                        }
                    }
                    .padding(.horizontal, gridSpacing)
                    .padding(.vertical, gridSpacing)
                    .animation(.smooth(duration: 0.3), value: metrics.columns.count) // iOS 26: smooth 动画

                    Text("敬请期待更多平台...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, gridSpacing)
                        .padding(.bottom, gridSpacing)
                }
                .scrollBounceBehavior(.basedOnSize) // iOS 26: 智能弹性滚动
                .navigationTitle("平台")
                .navigationBarTitleDisplayMode(.large)
            }
            .navigationDestination(for: Platformdescription.self) { platform in
                PlatformDetailViewControllerWrapper()
                    .environment(PlatformDetailViewModel(platform: platform))
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(platform.title)
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showCapabilitySheet = true
                            } label: {
                                Image(systemName: "info.circle")
                            }
                        }
                    }
                    .sheet(isPresented: $showCapabilitySheet) {
                        PlatformCapabilitySheet(liveType: platform.liveType)
                    }
            }
        }
    }

    @ViewBuilder
    private func platformNavigationItem(platform: Platformdescription, metrics: GridMetrics) -> some View {
        NavigationLink(value: platform) {
            PlatformCard(platform: platform)
                .frame(width: metrics.itemWidth, height: metrics.itemHeight)
        }
        .buttonStyle(PlatformCardButtonStyle())
    }

    private func columnCount(for size: CGSize) -> Int {
        guard size.width > 0 else { return 2 }

        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return 3
        case .phone:
            return 2
        default:
            let estimated = max(2, Int((size.width / 240).rounded(.down)))
            return min(6, estimated)
        }
    }

    private func layoutMetrics(for size: CGSize) -> GridMetrics {
        let columnsCount = max(1, columnCount(for: size))
        let horizontalPadding = gridSpacing * 2
        let interItemSpacing = gridSpacing * CGFloat(max(0, columnsCount - 1))
        let availableWidth = max(0, size.width - horizontalPadding - interItemSpacing)
        let itemWidth = columnsCount > 0 ? availableWidth / CGFloat(columnsCount) : 0
        let itemHeight = itemWidth * 0.6
        let gridColumns = Array(
            repeating: GridItem(.fixed(itemWidth), spacing: gridSpacing),
            count: columnsCount
        )
        return GridMetrics(columns: gridColumns, itemWidth: itemWidth, itemHeight: itemHeight)
    }
}

private struct GridMetrics {
    let columns: [GridItem]
    let itemWidth: CGFloat
    let itemHeight: CGFloat
}

// MARK: - Platform Card Component
struct PlatformCard: View {
    let platform: Platformdescription

    var body: some View {
        ZStack {
            Image("platform-bg")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            VStack(spacing: AppConstants.Spacing.md) {
                if let image = UIImage(named: platform.bigPic) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 80)
                } else {
                    Image(systemName: "play.tv")
                        .font(.system(size: 50))
                        .foregroundStyle(AppConstants.Colors.primaryText)
                }
            }
            .padding(AppConstants.Spacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl))
        .shadow(
            color: AppConstants.Shadow.lg.color,
            radius: AppConstants.Shadow.lg.radius,
            x: AppConstants.Shadow.lg.x,
            y: AppConstants.Shadow.lg.y
        )
        .contentShape(Rectangle())
    }
}

/// 平台卡片按钮样式 - 提供按压缩放效果
struct PlatformCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.bouncy(duration: 0.3), value: configuration.isPressed)
    }
}

extension Platformdescription: @retroactive Identifiable {
    public var id: String { title }
}

extension Notification.Name {
    static let switchToSettings = Notification.Name("switchToSettings")
}

#Preview {
    PlatformView()
}
