import Testing
@testable import AngelLiveCore

@Suite("Support diagnostic action context")
struct SupportDiagnosticActionContextTests {
    @Test("room context keeps public room identity and ignores empty fields")
    func roomContextKeepsPublicIdentity() {
        let room = LiveModel(
            userName: "fixture-anchor",
            roomTitle: "fixture-room",
            roomCover: "",
            userHeadImg: "",
            liveType: "fixture-source",
            liveState: nil,
            userId: "fixture-user",
            roomId: "fixture-room-id",
            liveWatchedCount: nil
        )

        let context = SupportDiagnosticActionContext.room(
            room,
            additional: ["entryPoint": "searchResult", "empty": "  "]
        )

        #expect(context["roomID"] == "fixture-room-id")
        #expect(context["anchorName"] == "fixture-anchor")
        #expect(context["roomTitle"] == "fixture-room")
        #expect(context["entryPoint"] == "searchResult")
        #expect(context["empty"] == nil)
        #expect(context["userID"] == nil)
    }

    @Test("selection and search contexts preserve reproducible request values")
    func selectionAndSearchContextsPreserveRequestValues() {
        let room = LiveModel(
            userName: "fixture-anchor",
            roomTitle: "fixture-room",
            roomCover: "",
            userHeadImg: "",
            liveType: "fixture-source",
            liveState: nil,
            userId: "fixture-user",
            roomId: "fixture-room-id",
            liveWatchedCount: nil
        )

        let selection = SupportDiagnosticActionContext.selection(
            room: room,
            lineIndex: 1,
            lineName: "fixture-line",
            qualityIndex: 2,
            qualityName: "fixture-quality",
            playerKernel: "fixture-kernel",
            additional: ["selection": "automatic"]
        )
        let keyword = SupportDiagnosticActionContext.search(
            keyword: " fixture-query ",
            page: 2,
            additional: ["searchKind": "keyword"]
        )
        let share = SupportDiagnosticActionContext.shareSearch()

        #expect(selection["lineIndex"] == "1")
        #expect(selection["lineName"] == "fixture-line")
        #expect(selection["qualityIndex"] == "2")
        #expect(selection["qualityName"] == "fixture-quality")
        #expect(selection["playerKernel"] == "fixture-kernel")
        #expect(selection["selection"] == "automatic")
        #expect(keyword["query"] == " fixture-query ")
        #expect(keyword["page"] == "2")
        #expect(keyword["searchKind"] == "keyword")
        #expect(share == ["searchKind": "share"])
    }
}
