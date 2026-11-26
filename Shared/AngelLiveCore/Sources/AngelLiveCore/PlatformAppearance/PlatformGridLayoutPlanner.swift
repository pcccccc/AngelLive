import Foundation

public struct PlatformGridLayoutPlanner: Sendable {
    public struct Placement: Equatable, Sendable {
        public let row: Int
        public let column: Int
        public let span: Int
        public let x: Double
        public let width: Double
    }

    public let columnCount: Int
    public let spacing: Double
    public let horizontalPadding: Double
    public let unitWidth: Double

    public init(containerWidth: Double, columnsCount: Int, spacing: Double, horizontalPadding: Double) {
        columnCount = max(1, columnsCount)
        self.spacing = max(0, spacing.isFinite ? spacing : 0)
        self.horizontalPadding = max(0, horizontalPadding.isFinite ? horizontalPadding : 0)
        let width = max(0, containerWidth.isFinite ? containerWidth : 0)
        unitWidth = max(0, width - 2 * self.horizontalPadding - self.spacing * Double(columnCount - 1))
            / Double(columnCount)
    }

    public func placements(spansTwoColumns: [Bool]) -> [Placement] {
        var row = 0
        var column = 0
        return spansTwoColumns.map { wantsTwo in
            let span = wantsTwo && columnCount >= 2 ? 2 : 1
            if column + span > columnCount {
                row += 1
                column = 0
            }
            let placement = Placement(
                row: row, column: column, span: span,
                x: horizontalPadding + Double(column) * (unitWidth + spacing),
                width: Double(span) * unitWidth + Double(span - 1) * spacing
            )
            column += span
            return placement
        }
    }
}
