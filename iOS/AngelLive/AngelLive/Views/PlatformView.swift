//
//  PlatformView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct PlatformView: View {
    @Environment(PlatformViewModel.self) private var viewModel
    @State private var navigationPath: [Platformdescription] = []
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
                            NavigationLink(value: platform) {
                                PlatformCard(platform: platform)
                                    .frame(width: metrics.itemWidth, height: metrics.itemHeight)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, gridSpacing)
                    .padding(.vertical, gridSpacing)
                    .animation(.easeInOut(duration: 0.3), value: metrics.columns.count)

                    Text("敬请期待更多平台...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, gridSpacing)
                        .padding(.bottom, gridSpacing)
                }
                .navigationTitle("平台")
                .navigationBarTitleDisplayMode(.large)
            }
            .navigationDestination(for: Platformdescription.self) { platform in
                PlatformDetailViewControllerWrapper()
                    .environment(PlatformDetailViewModel(platform: platform))
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle(platform.title)
            }
        }
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
    @State private var isPressed = false

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
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .shadow(
            color: AppConstants.Shadow.lg.color,
            radius: AppConstants.Shadow.lg.radius,
            x: AppConstants.Shadow.lg.x,
            y: AppConstants.Shadow.lg.y
        )
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

extension Platformdescription: Identifiable {
    public var id: String { title }
}

#Preview {
    PlatformView()
}
