import CoreGraphics
import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Danmaku mixed content layout")
struct DanmakuMixedCellModelTests {
    @Test("text and images keep source order and share one measured cell")
    func laysOutOrderedSegments() throws {
        let image = try #require(makeImage(width: 80, height: 40))
        let model = DanmakuMixedCellModel(
            segments: [
                .text("before"),
                .image(image, pixelSize: CGSize(width: 80, height: 40)),
                .text("after")
            ],
            font: .systemFont(ofSize: 20)
        )

        #expect(model.layoutItems.count == 3)
        #expect(model.layoutItems[0].rect.maxX < model.layoutItems[1].rect.minX)
        #expect(model.layoutItems[1].rect.maxX < model.layoutItems[2].rect.minX)
        #expect(model.size.width > model.layoutItems[2].rect.maxX)
        #expect(model.size.height >= model.layoutItems[1].rect.height)
        #expect(model.cellClass == DanmakuMixedCell.self)
    }

    @Test("extremely wide images are capped to four times their inline height")
    func capsImageAspectRatio() throws {
        let image = try #require(makeImage(width: 1_000, height: 10))
        let model = DanmakuMixedCellModel(
            segments: [.image(image, pixelSize: CGSize(width: 1_000, height: 10)), .text("ok")],
            font: .systemFont(ofSize: 20)
        )

        let imageRect = try #require(model.layoutItems.first?.rect)
        #expect(imageRect.width / imageRect.height <= 4.001)
    }

    @Test("shared resolver preserves content order and merges adjacent text")
    func resolvesTextSegmentsForAllPresentationSurfaces() async throws {
        let resolved = await DanmakuContentResolver.resolve([
            .text("hello"),
            .text(" world")
        ])

        #expect(resolved.count == 1)
        guard case .text(let text) = try #require(resolved.first) else {
            Issue.record("Expected a resolved text segment")
            return
        }
        #expect(text == "hello world")
    }

    @MainActor
    @Test("immediate text matches resolved content and style")
    func immediateTextModel() async throws {
        for (segments, expected) in [
            ([DanmakuDisplaySegment.text("hello"), .text(""), .text(" "), .text("world")], "hello world"),
            ([.text("")], "fallback"),
            ([], "fallback")
        ] {
            let message = DanmakuDisplayMessage(text: "fallback", nickname: "", color: 0x2277AA, segments: segments)
            let immediate = try #require(DanmakuDisplayModelFactory.makeImmediateModelIfAvailable(
                for: message, showColorDanmu: true, alpha: 0.6, fontSize: 20
            ) as? DanmakuTextCellModel)
            let resolved = await DanmakuDisplayModelFactory.makeModel(
                for: message, showColorDanmu: true, alpha: 0.6, fontSize: 20
            )
            let text = try #require(resolved as? DanmakuTextCellModel)
            #expect(immediate.text == expected)
            #expect(immediate.text == text.text)
            #expect(immediate.color == text.color)
            #expect(immediate.size == text.size)
            #expect(immediate.font.pointSize == 20)
            #expect((8.5...11.5).contains(immediate.displayTime))
        }
    }

    @MainActor
    @Test("image segments use deferred decoding and retain their position")
    func imageModelRequiresResolution() async throws {
        // A one-pixel GIF exercises the image loader without a network request.
        let url = try #require(URL(string: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="))
        let message = DanmakuDisplayMessage(
            text: "fallback", nickname: "", color: 0xFFFFFF,
            segments: [.text("left"), .image(.init(url: url, pixelSize: nil)), .text("right")]
        )
        let immediate = DanmakuDisplayModelFactory.makeImmediateModelIfAvailable(
            for: message, showColorDanmu: false, alpha: 1, fontSize: 20
        )
        #expect(immediate == nil)
        let resolved = await DanmakuDisplayModelFactory.makeModel(
            for: message, showColorDanmu: false, alpha: 1, fontSize: 20
        )
        let mixed = try #require(resolved as? DanmakuMixedCellModel)
        try #require(mixed.segments.count == 3)
        guard case .text("left") = mixed.segments[0],
              case .image(let image, _) = mixed.segments[1],
              case .text("right") = mixed.segments[2] else {
            Issue.record("Expected the decoded image between the original text segments")
            return
        }
        #expect(image.width == 1 && image.height == 1)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}
