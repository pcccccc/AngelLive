import UIKit
import SwiftUI
import JXSegmentedView

/// Shared by the platform room list and the history content pages.
@MainActor
enum FullUIMainCategoryStyle {
    static let height: CGFloat = 56

    static func configure(_ view: JXSegmentedView, dataSource: JXSegmentedTitleDataSource) {
        view.backgroundColor = UIColor(AppConstants.Colors.primaryBackground)
        view.dataSource = dataSource
        view.contentEdgeInsetLeft = 20
        view.contentEdgeInsetRight = 20

        dataSource.isItemSpacingAverageEnabled = false
        dataSource.titleNormalColor = UIColor(AppConstants.Colors.primaryText)
        dataSource.titleSelectedColor = UIColor(AppConstants.Colors.primaryText)
        dataSource.titleNormalFont = .systemFont(ofSize: 21, weight: .bold)
        dataSource.titleSelectedFont = .systemFont(ofSize: 22, weight: .heavy)
        dataSource.isTitleZoomEnabled = true
        dataSource.titleSelectedZoomScale = 1.1
        dataSource.itemWidth = JXSegmentedViewAutomaticDimension
        dataSource.itemSpacing = 16

        let indicator = JXSegmentedIndicatorLineView()
        indicator.indicatorWidth = 20
        indicator.indicatorColor = UIColor(AppConstants.Colors.accent)
        indicator.indicatorHeight = 4
        indicator.indicatorCornerRadius = 2
        indicator.verticalOffset = 2
        view.indicators = [indicator]
    }
}
