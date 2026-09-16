import CoreGraphics
import Testing
@testable import AngelLiveCore

@Suite("Danmaku text outline style")
struct DanmakuTextOutlineStyleTests {

    @Test("uses a five percent outline width")
    func usesFontRelativeOutlineWidth() {
        #expect(DanmakuTextOutlineStyle.strokePercentage == -5)
    }

    @Test("uses a white outline only for nearly black text")
    func contrastingOutlineColor() {
        let dark = DanmakuTextOutlineStyle.outlineColor(red: 0.05, green: 0.05, blue: 0.05)
        let bright = DanmakuTextOutlineStyle.outlineColor(red: 1, green: 1, blue: 1)

        #expect(components(of: dark) == RGBA(red: 1, green: 1, blue: 1, alpha: 1))
        #expect(components(of: bright) == RGBA(red: 0, green: 0, blue: 0, alpha: 1))
    }

    private func components(of color: DanmakuColor) -> RGBA {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let converted = color.danmakuGetRGBA(&red, &green, &blue, &alpha)
        #expect(converted)
        return RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    private struct RGBA: Equatable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }
}

#if os(macOS)
import AppKit

@Suite("Danmaku text drawing rasterization")
@MainActor
struct DanmakuTextDrawingTests {
    @Test("applies translucent text alpha once to a transparent bitmap")
    func compositesTranslucentTextAsOneLayer() throws {
        let bitmap = try #require(makeBitmap())
        drawText(in: bitmap.context, color: .white.withAlphaComponent(0.6))

        let pixels = bitmap.pixels()
        let maximumAlpha = pixels.map(\.alpha).max() ?? 0

        #expect(maximumAlpha > 0.1)
        #expect(maximumAlpha <= 0.61)
    }

    @Test("keeps a translucent white glyph bright on a light background")
    func keepsWhiteGlyphCoreFreeOfOutlineContamination() throws {
        let bitmap = try #require(makeBitmap())
        bitmap.context.setFillColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
        bitmap.context.fill(bitmap.bounds)
        drawText(in: bitmap.context, color: .white.withAlphaComponent(0.6))

        let maximumBrightness = bitmap.pixels().map { max($0.red, $0.green, $0.blue) }.max() ?? 0

        #expect(maximumBrightness > 0.86)
    }

    @Test("restores CGContext alpha before subsequent drawing")
    func restoresContextState() throws {
        let bitmap = try #require(makeBitmap())
        drawText(in: bitmap.context, color: .white.withAlphaComponent(0.6))
        bitmap.context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        bitmap.context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))

        let hasOpaqueRedPixel = bitmap.pixels().contains {
            $0.red > 0.99 && $0.green < 0.01 && $0.blue < 0.01 && $0.alpha > 0.99
        }
        #expect(hasOpaqueRedPixel)
    }

    private func drawText(in context: CGContext, color: DanmakuColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }

        DanmakuTextDrawing.draw(
            "H",
            font: .systemFont(ofSize: 32),
            color: color,
            at: CGPoint(x: 20, y: 20),
            in: context
        )
    }

    private func makeBitmap() -> Bitmap? {
        Bitmap(width: 96, height: 96)
    }

    private struct Bitmap {
        let width: Int
        let height: Int
        let context: CGContext

        init?(width: Int, height: Int) {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return nil
            }

            self.width = width
            self.height = height
            self.context = context
        }

        var bounds: CGRect {
            CGRect(x: 0, y: 0, width: width, height: height)
        }

        func pixels() -> [RGBA] {
            (0..<(width * height)).map { index in
                pixel(at: index)
            }
        }

        private func pixel(at index: Int) -> RGBA {
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            let offset = index * 4
            return RGBA(
                red: CGFloat(bytes[offset]) / 255,
                green: CGFloat(bytes[offset + 1]) / 255,
                blue: CGFloat(bytes[offset + 2]) / 255,
                alpha: CGFloat(bytes[offset + 3]) / 255
            )
        }
    }

    private struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }
}
#endif
