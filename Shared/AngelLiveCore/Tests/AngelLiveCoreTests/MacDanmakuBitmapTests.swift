#if os(macOS)
import AppKit
import Testing
@testable import AngelLiveCore

@MainActor
struct MacDanmakuBitmapTests {
    @Test(arguments: [2, 3], [false, true])
    func rendersCells(scale: Int, asynchronous: Bool) async throws {
        let source = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        source.setFillColor(NSColor.red.cgColor)
        source.fill(CGRect(x: 0, y: 4, width: 8, height: 4))
        source.setFillColor(NSColor.blue.cgColor)
        source.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        let image = try #require(source.makeImage())
        let font = NSFont.boldSystemFont(ofSize: 20)
        let models: [DanmakuCellModel] = [
            DanmakuTextCellModel(str: "F", strFont: font),
            DanmakuImageCellModel(image: image, pixelSize: nil, font: font),
            DanmakuMixedCellModel(segments: [.text("F"), .image(image, pixelSize: nil)], font: font)
        ]
        for model in models {
            let cell = model.cellClass.init(frame: CGRect(x: 0, y: 0, width: 140, height: 44))
            cell.model = model
            let layer = DanmakuAsyncLayer()
            layer.bounds = cell.bounds
            layer.contentsScale = CGFloat(scale)
            layer.displayAsync = asynchronous
            layer.usesBitmapRendering = true
            layer.displaying = try #require((cell.layer as? DanmakuAsyncLayer)?.displaying)
            defer { withExtendedLifetime(cell) {} }
            let finished = await withCheckedContinuation { continuation in
                layer.didDisplay = { _, finished in continuation.resume(returning: finished) }
                layer.display()
            }
            try #require(finished)
            let contents = try #require(layer.contents)
            try #require(CFGetTypeID(contents as CFTypeRef) == CGImage.typeID)
            let bitmap = contents as! CGImage
            #expect(bitmap.width == 140 * scale)
            #expect(bitmap.height == 44 * scale)
            let data = try #require(bitmap.dataProvider?.data)
            let bytes = try #require(CFDataGetBytePtr(data))
            var glyphRows = [Int](repeating: 0, count: bitmap.height)
            var redRows = [Int]()
            var blueRows = [Int]()
            for y in 0..<bitmap.height {
                for x in 0..<bitmap.width {
                    let pixel = bytes + y * bitmap.bytesPerRow + x * 4
                    guard pixel[3] > 200 else { continue }
                    if pixel[0] > 200 && pixel[2] < 30 { redRows.append(y) }
                    if pixel[2] > 200 && pixel[0] < 30 { blueRows.append(y) }
                    if pixel[0] > 200 && pixel[1] > 200 && pixel[2] > 200 { glyphRows[y] += 1 }
                }
            }
            if !(model is DanmakuTextCellModel) {
                let bottomOfRed = try #require(redRows.max())
                let topOfBlue = try #require(blueRows.min())
                #expect(bottomOfRed < topOfBlue)
            }
            if !(model is DanmakuImageCellModel) {
                let top = try #require(glyphRows.firstIndex { $0 > 0 })
                let bottom = try #require(glyphRows.lastIndex { $0 > 0 })
                let middle = (top + bottom) / 2
                // An upright F has more white ink in its upper half.
                #expect(glyphRows[top..<middle].reduce(0, +) > glyphRows[middle...bottom].reduce(0, +))
            }
        }
    }
}
#endif
