#if canImport(UIKit)
import CoreGraphics
import Testing
import UIKit
@testable import AngelLiveCore

@Suite("Danmaku text UIKit vertical alignment")
@MainActor
struct DanmakuTextVerticalAlignmentTests {
    private let containerHeight: CGFloat = 270
    private let paddingTop: CGFloat = 5
    private let text = "alignment"
    private let tolerance: CGFloat = 0.001

    @Test(
        "centers the measured text in the first track across font sizes",
        arguments: [50, 60, 64, 65, 70]
    )
    func centersTextInFirstTrack(_ fontSize: Int) throws {
        let font = UIFont.systemFont(ofSize: CGFloat(fontSize))
        let model = DanmakuTextCellModel(str: text, strFont: font)
        let view = DanmakuView(
            frame: CGRect(x: 0, y: 0, width: 1920, height: containerHeight)
        )
        defer { view.stop() }

        view.paddingTop = paddingTop
        view.trackHeight = CGFloat(fontSize) * 1.35
        view.play()
        view.shoot(danmaku: model)

        let cell = try #require(view.subviews.compactMap { $0 as? DanmakuTextCell }.first)
        let textSize = NSString(string: text).size(withAttributes: [.font: font])
        let verticalPadding = CGFloat(fontSize) * 0.5 + 12
        let drawingRect = CGRect(
            x: cell.frame.minX + model.textDrawingOrigin.x,
            y: cell.frame.minY + model.textDrawingOrigin.y,
            width: textSize.width,
            height: textSize.height
        )

        let trackHeight = CGFloat(fontSize) * 1.35
        let trackCount = floor((containerHeight - paddingTop) / trackHeight)
        let offsetY = max(0, (containerHeight - trackCount * trackHeight) / 2)
        let firstTrackCenterY = trackHeight / 2 + paddingTop + offsetY
        let firstTrackRect = CGRect(
            x: 0,
            y: firstTrackCenterY - trackHeight / 2,
            width: view.bounds.width,
            height: trackHeight
        )

        #expect(model.track == 0)
        #expect(abs(cell.frame.midY - firstTrackCenterY) <= tolerance)
        #expect(abs(drawingRect.midY - cell.frame.midY) <= tolerance)
        #expect(drawingRect.minY >= -tolerance)
        #expect(drawingRect.maxY <= containerHeight + tolerance)
        #expect(firstTrackRect.minY >= -tolerance)
        #expect(firstTrackRect.maxY <= containerHeight + tolerance)

        // The alignment origin must not change the established size or track-height formulas.
        #expect(abs(model.size.width - (textSize.width + CGFloat(fontSize) + 25)) <= tolerance)
        #expect(abs(model.size.height - (textSize.height + verticalPadding)) <= tolerance)
        #expect(abs(view.trackHeight - trackHeight) <= tolerance)
        #expect(abs(model.textDrawingOrigin.x - 25) <= tolerance)
        #expect(abs(model.textDrawingOrigin.y - verticalPadding / 2) <= tolerance)
    }
}
#endif
