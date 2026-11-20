import SwiftUI

enum PluginManagementLayout {
    static let pageInset: CGFloat = 16
    static let contentInset: CGFloat = 16
    static let collapsedRemovalInset: CGFloat = 4
    static let headerToCard: CGFloat = 8
    static let sectionSpacing: CGFloat = 27
    static let cardRadius: CGFloat = 22
    static let iconSize: CGFloat = 48
    static let iconRadius: CGFloat = 12
    static let iconTextSpacing: CGFloat = 12
    static let rowVerticalInset: CGFloat = 13
    static let summaryVerticalInset: CGFloat = 14
    static let textSpacing: CGFloat = 2
    static let itemSpacing: CGFloat = 8
    static let detailSpacing: CGFloat = 20
    static let readingWidth: CGFloat = 680
    static let minimumTarget: CGFloat = 44
    static let primaryAction: Color = .blue
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let primaryText = Color(uiColor: .label)
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let rowInsets = EdgeInsets(top: 0, leading: contentInset, bottom: 0, trailing: contentInset)
    static let zeroInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

/// Includes the full native header and touch target, while measuring spacing to visible title ink.
struct PluginManagementHeadingGap: Layout {
    let inkAscent: CGFloat
    let sectionSpacing: CGFloat
    var includesSectionSpacing = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let dimensions = content.dimensions(in: ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: dimensions.width, height: dimensions.height + topInset(for: dimensions))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let contentProposal = ProposedViewSize(width: bounds.width, height: nil)
        let dimensions = content.dimensions(in: contentProposal)
        content.place(at: CGPoint(x: bounds.minX, y: bounds.minY + topInset(for: dimensions)), anchor: .topLeading, proposal: contentProposal)
    }

    private func topInset(for dimensions: ViewDimensions) -> CGFloat {
        guard includesSectionSpacing else { return 0 }
        let inkTop = dimensions[.firstTextBaseline] - inkAscent
        return max(0, sectionSpacing - inkTop)
    }
}

struct PluginManagementSectionGap: View {
    var body: some View {
        Color.clear.frame(height: PluginManagementLayout.sectionSpacing)
            .accessibilityHidden(true)
            .listRowInsets(PluginManagementLayout.zeroInsets)
    }
}

struct PluginManagementFooter: View {
    let text: LocalizedStringResource
    var body: some View {
        PluginManagementEdgeText(text: text, style: .footnote).foregroundStyle(PluginManagementLayout.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, PluginManagementLayout.headerToCard)
            .listRowInsets(PluginManagementLayout.zeroInsets)
    }
}
