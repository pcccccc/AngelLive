#if os(iOS)
import CoreGraphics
import ImageIO
import QuartzCore
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import AngelLiveCore

@Suite("Danmaku local display scale")
@MainActor
struct DanmakuDisplayScaleTests {
    @Test("trait changes rerasterize at the new pixel size without replacing motion or model")
    func rerasterizesForChangedDisplayScale() throws {
        let cell = DanmakuCell(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        let layer = try #require(cell.layer as? DanmakuAsyncLayer)
        let model = DanmakuTextCellModel(str: "fixture", strFont: .systemFont(ofSize: 15))
        cell.model = model
        cell.displayAsync = false
        layer.displaying = { context, size, _ in
            context.setFillColor(UIColor.red.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
        let movement = CABasicAnimation(keyPath: "position.x")
        movement.duration = 10
        layer.add(movement, forKey: "fixture.motion")

        cell.traitOverrides.displayScale = 2
        cell.updateTraitsIfNeeded()
        layer.displayIfNeeded()
        let first = try #require(layer.contents as? CGImage)
        #expect(layer.contentsScale == 2)
        #expect(first.width == 80 && first.height == 40)

        cell.traitOverrides.displayScale = 2
        cell.updateTraitsIfNeeded()
        #expect(!layer.needsDisplay())

        cell.traitOverrides.displayScale = 3
        cell.updateTraitsIfNeeded()
        #expect(layer.needsDisplay())
        layer.displayIfNeeded()
        let second = try #require(layer.contents as? CGImage)
        #expect(layer.contentsScale == 3)
        #expect(second.width == 120 && second.height == 60)
        #expect((cell.model as? DanmakuTextCellModel) === model)
        #expect(layer.animation(forKey: "fixture.motion")?.duration == 10)
    }

    @Test("image and mixed cells use the raster context scale", arguments: [2, 3])
    func rendersImagesAtContextScale(_ scale: Int) throws {
        let image = try makeImage()
        let imageModel = DanmakuImageCellModel(image: image, pixelSize: nil, font: .systemFont(ofSize: 15))
        let mixedModel = DanmakuMixedCellModel(
            segments: [.text("fixture"), .image(image, pixelSize: nil)],
            font: .systemFont(ofSize: 15)
        )
        let cells: [DanmakuCell] = [
            DanmakuImageCell(frame: CGRect(x: 0, y: 0, width: 100, height: 40)),
            DanmakuMixedCell(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        ]
        cells[0].model = imageModel
        cells[1].model = mixedModel

        for cell in cells {
            cell.displayAsync = false
            cell.traitOverrides.displayScale = CGFloat(scale)
            cell.updateTraitsIfNeeded()
            cell.redraw()
            cell.layer.displayIfNeeded()
            let bitmap = try #require(cell.layer.contents as? CGImage)
            #expect(bitmap.width == 100 * scale)
            #expect(bitmap.height == 40 * scale)
        }
    }

    @Test("changing GIF display scale preserves its current frame and animator")
    func preservesGIFFrameAndAnimator() throws {
        let image = try makeImage()
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let cell = DanmakuGifCell(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        cell.model = FixtureGIFModel(resource: data as Data)
        cell.traitOverrides.displayScale = 2
        cell.updateTraitsIfNeeded()
        cell.layer.displayIfNeeded()
        cell.enterTrack()
        defer { cell.leaveTrack() }
        let animator = try #require(cell.animator)
        animator.stopAnimation()
        cell.layer.contents = image
        let frameIndex = animator.currentFrameIndex

        cell.traitOverrides.displayScale = 3
        cell.updateTraitsIfNeeded()
        cell.layer.displayIfNeeded()
        let retainedImage = try #require(cell.layer.contents as? CGImage)
        #expect(cell.layer.contentsScale == 3)
        #expect(retainedImage === image)
        #expect(cell.animator === animator)
        #expect(animator.currentFrameIndex == frameIndex)
    }

    private func makeImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }
}

private final class FixtureGIFModel: DanmakuGifCellModel {
    let resource: Data?
    let identifier = "fixture.gif"
    let size = CGSize(width: 40, height: 20)
    var track: UInt?
    let displayTime: Double = 10
    let type: DanmakuCellType = .floating
    var cellClass: DanmakuCell.Type { DanmakuGifCell.self }

    init(resource: Data) { self.resource = resource }
    func isEqual(to cellModel: DanmakuCellModel) -> Bool { identifier == cellModel.identifier }
}
#endif
