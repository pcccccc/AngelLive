import CoreGraphics
import Testing
@testable import AngelLiveCore

@Suite("Danmaku track selection")
@MainActor
struct DanmakuTrackSelectionTests {

    @Test("uses top-first collision-safe tracks by default")
    func defaultsToTopPriority() {
        let view = DanmakuView(frame: CGRect(x: 0, y: 0, width: 600, height: 120))

        switch view.floatingTrackPolicy {
        case .topPriority:
            break
        case .scattered:
            Issue.record("DanmakuView must prefer the first collision-safe track")
        }
    }

    @Test("moves down only while the first track is not yet safe")
    func usesNextTrackWhenFirstTrackIsOccupied() {
        let view = DanmakuView(frame: CGRect(x: 0, y: 0, width: 600, height: 120))
        view.trackHeight = 40
        view.play()

        let first = makeModel("first", identifier: "first")
        let second = makeModel("second", identifier: "second")

        view.shoot(danmaku: first)
        view.shoot(danmaku: second)

        #expect(first.track == 0)
        #expect(second.track == 1)
    }

    @Test("reuses the first track after its previous danmaku is nearly gone")
    func reusesFirstTrackWhenPreviousDanmakuIsNearlyGone() {
        let view = DanmakuView(frame: CGRect(x: 0, y: 0, width: 600, height: 120))
        view.trackHeight = 40
        view.play()

        let nearlyGone = makeModel("old", identifier: "old")
        view.sync(danmaku: nearlyGone, at: 0.9)

        let next = makeModel("new", identifier: "new")
        view.shoot(danmaku: next)

        #expect(nearlyGone.track == 0)
        #expect(next.track == 0)
    }

    private func makeModel(_ text: String, identifier: String) -> DanmakuTextCellModel {
        let model = DanmakuTextCellModel(str: text, strFont: .systemFont(ofSize: 16))
        model.identifier = identifier
        model.displayTime = 10
        return model
    }
}
