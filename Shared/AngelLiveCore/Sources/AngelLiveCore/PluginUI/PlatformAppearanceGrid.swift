import SwiftUI

/// The same layout positions every slot, including wide cards, without regrouping card identities by row.
public struct PlatformAppearanceGridLayout: Layout {
    public let idiom: PlatformDeviceIdiom
    public let density: PlatformGridDensity
    public let aspect: PlatformCardAspectPreset
    public let metrics: PlatformIdiomCustomMetrics
    public let spacing: CGFloat
    public let horizontalPadding: CGFloat

    public init(
        idiom: PlatformDeviceIdiom,
        density: PlatformGridDensity,
        aspect: PlatformCardAspectPreset,
        metrics: PlatformIdiomCustomMetrics,
        spacing: CGFloat,
        horizontalPadding: CGFloat
    ) {
        self.idiom = idiom
        self.density = density
        self.aspect = aspect
        self.metrics = metrics
        self.spacing = spacing
        self.horizontalPadding = horizontalPadding
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width =
            proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 2 * horizontalPadding + spacing + 2 * 180
        let (placements, height) = grid(width: width, subviews: subviews)
        let rows = placements.last.map { $0.row + 1 } ?? 0
        return CGSize(width: width, height: CGFloat(rows) * height + CGFloat(max(0, rows - 1)) * spacing)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let (placements, height) = grid(width: bounds.width, subviews: subviews)
        for (subview, placement) in zip(subviews, placements) {
            let x =
                subviews.layoutDirection == .leftToRight
                ? bounds.minX + placement.x
                : bounds.maxX - placement.x - placement.width
            subview.place(
                at: CGPoint(x: x, y: bounds.minY + CGFloat(placement.row) * (height + spacing)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: placement.width, height: height)
            )
        }
    }

    func planner(for width: CGFloat) -> PlatformGridLayoutPlanner {
        let columns =
            metrics.useCustomMetrics
            ? metrics.columns
            : density.columns(
                for: idiom,
                availableWidth: width - 2 * horizontalPadding,
                spacing: spacing
            )
        return PlatformGridLayoutPlanner(
            containerWidth: width,
            columnsCount: columns,
            spacing: spacing,
            horizontalPadding: horizontalPadding
        )
    }

    func cardHeight(unitWidth: CGFloat) -> CGFloat {
        let height = metrics.useCustomMetrics ? metrics.cardHeight : unitWidth * aspect.heightToWidth
        let minimumHeight: CGFloat = idiom == .tv ? 130 : 52
        return max(minimumHeight, height)
    }

    private func grid(width: CGFloat, subviews: Subviews) -> ([PlatformGridLayoutPlanner.Placement], CGFloat) {
        let planner = planner(for: width)
        return (
            planner.placements(spansTwoColumns: subviews.map { $0[PlatformAppearanceGridSpan.self] }),
            cardHeight(unitWidth: planner.unitWidth)
        )
    }
}

private struct PlatformAppearanceGridSpan: LayoutValueKey {
    static let defaultValue = false
}

public extension View {
    func platformAppearanceGridSpan(_ spansTwoColumns: Bool) -> some View {
        layoutValue(key: PlatformAppearanceGridSpan.self, value: spansTwoColumns)
    }
}

// MARK: - Card Menu

public struct PlatformAppearanceCardActions: View {
    private let pluginID: String
    private let orderedIDs: [String]
    private let onCustomize: () -> Void
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    public init(
        pluginID: String,
        orderedIDs: [String],
        onCustomize: @escaping () -> Void
    ) {
        self.pluginID = pluginID
        self.orderedIDs = orderedIDs
        self.onCustomize = onCustomize
    }

    public var body: some View {
        let index = orderedIDs.firstIndex(of: pluginID)
        let spans = store.snapshot.appearance(for: pluginID).spansTwoColumns
        Button(
            "自定义卡片外观…",
            systemImage: "slider.horizontal.3",
            action: onCustomize
        )
        .accessibilityIdentifier("platform.card.customize")
        Button(spans ? "恢复单列展示" : "跨两列展示", systemImage: "rectangle.split.2x1") {
            store.updateCard(pluginID) { $0.spansTwoColumns.toggle() }
        }
        Button("前移一位", systemImage: "arrow.up") {
            store.move(
                pluginID,
                by: -1,
                among: orderedIDs
            )
        }
        .disabled(index == nil || index == orderedIDs.indices.first)
        Button("后移一位", systemImage: "arrow.down") {
            store.move(
                pluginID,
                by: 1,
                among: orderedIDs
            )
        }
        .disabled(index == nil || index == orderedIDs.indices.last)
        Button(
            "恢复默认外观",
            systemImage: "arrow.counterclockwise",
            role: .destructive
        ) {
            store.resetCard(pluginID)
        }
        .disabled(store.snapshot.cardOverrides[pluginID] == nil)
    }
}
