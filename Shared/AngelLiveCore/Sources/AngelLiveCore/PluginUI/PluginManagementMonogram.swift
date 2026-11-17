import SwiftUI
import CoreText

/// Shared, deterministic presentation for management icons without an image.
public struct PluginManagementMonogramStyle: Sendable {
    public let glyph: String
    public let paletteIndex: Int

    private static let palette: [(Double, Double, Double)] = [
        (0.84, 0.86, 0.88),
        (0.87, 0.85, 0.82),
        (0.83, 0.87, 0.85),
        (0.87, 0.84, 0.87),
        (0.86, 0.87, 0.82),
        (0.82, 0.86, 0.88)
    ]

    public init(pluginID: String, displayName: String) {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = (name.isEmpty ? pluginID : name).first.map(String.init) ?? "?"
        glyph = String(first.uppercased(with: Locale(identifier: "en_US_POSIX")).prefix(1))
        var hash: UInt64 = 14695981039346656037
        for byte in pluginID.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        paletteIndex = Int(hash % UInt64(Self.palette.count))
    }

    public var backgroundRGB: (red: Double, green: Double, blue: Double) {
        Self.palette[paletteIndex]
    }

    public static let cornerFraction: CGFloat = 0.25

    /// The outer icon slot stays unchanged; only the actual bitmap drawing is capped.
    public static func bitmapDrawSize(
        pixelWidth: Int, pixelHeight: Int, targetSide: CGFloat, displayScale: CGFloat
    ) -> CGSize {
        guard pixelWidth > 0, pixelHeight > 0, targetSide > 0,
              displayScale.isFinite, displayScale > 0 else { return .zero }
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)
        let factor = min(targetSide / width, targetSide / height, 1 / displayScale)
        return CGSize(width: width * factor, height: height * factor)
    }
}

public struct PluginManagementMonogram: View {
    private let style: PluginManagementMonogramStyle
    private let size: CGFloat

    public init(pluginID: String, displayName: String, size: CGFloat) {
        style = PluginManagementMonogramStyle(pluginID: pluginID, displayName: displayName)
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let fontSize = min(canvasSize.width, canvasSize.height) * 0.48
            let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
                ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(srgbRed: 0.18, green: 0.21, blue: 0.25, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: style.glyph, attributes: attributes) as CFAttributedString
            )
            let ink = CTLineGetImageBounds(line, nil)
            context.withCGContext { cg in
                cg.translateBy(x: 0, y: canvasSize.height)
                cg.scaleBy(x: 1, y: -1)
                cg.textMatrix = .identity
                cg.textPosition = CGPoint(
                    x: canvasSize.width / 2 - ink.midX,
                    y: canvasSize.height / 2 - ink.midY
                )
                CTLineDraw(line, cg)
            }
        }
        .frame(width: size, height: size)
        .background(
            Color(.sRGB, red: style.backgroundRGB.red, green: style.backgroundRGB.green,
                  blue: style.backgroundRGB.blue, opacity: 1),
            in: RoundedRectangle(cornerRadius: size * PluginManagementMonogramStyle.cornerFraction, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}
