import SwiftUI
import UIKit
import CoreText

/// Aligns the font's visible outline with the adjacent card, retaining Text's native baseline.
struct PluginManagementEdgeText: View {
    enum Style {
        case sectionTitle, headline, footnote

        var textStyle: UIFont.TextStyle {
            switch self {
            case .sectionTitle: .title3
            case .headline: .headline
            case .footnote: .footnote
            }
        }
    }

    let text: LocalizedStringResource
    let style: Style
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let metrics = PluginManagementTextMetrics(text: text, style: style, locale: locale, dynamicTypeSize: dynamicTypeSize)
        let ink = metrics.inkBounds
        // The correction comes from the same resolved font and localized glyphs that Text renders.
        // It removes a side bearing, rather than introducing a title-specific layout inset.
        let correction = ink.isNull ? 0 : (layoutDirection == .leftToRight ? -ink.minX : metrics.advance - ink.maxX)

        Text(verbatim: metrics.value)
            .font(Font(metrics.font))
            .offset(x: correction)
    }
}

@MainActor
struct PluginManagementTextMetrics {
    let value: String
    let font: UIFont
    let inkBounds: CGRect
    let advance: CGFloat

    init(text: LocalizedStringResource, style: PluginManagementEdgeText.Style, locale: Locale, dynamicTypeSize: DynamicTypeSize) {
        var resource = text
        resource.locale = locale
        value = String(localized: resource)
        let traits = UITraitCollection(preferredContentSizeCategory: Self.contentSizeCategory(for: dynamicTypeSize))
        let preferred = UIFont.preferredFont(forTextStyle: style.textStyle, compatibleWith: traits)
        let descriptor = style == .sectionTitle
            ? preferred.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold.rawValue]])
            : preferred.fontDescriptor
        font = UIFont(descriptor: descriptor, size: preferred.pointSize)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font]))
        inkBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func contentSizeCategory(for dynamicTypeSize: DynamicTypeSize) -> UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
