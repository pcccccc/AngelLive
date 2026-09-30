import Testing
@testable import AngelLiveCore

@Suite("Danmaku language detection")
struct DanmakuLanguageDetectionTests {
    @Test(arguments: ["네", "와!", "안녕", "ㅋㅋ", "ㅎㅎ 😊", "고마워요", "123 네 👍"])
    func shortHangulRepliesAreRecognized(_ text: String) {
        #expect(NaturalDanmakuLanguageDetector().sourceLanguage(for: text) == "ko")
    }

    @Test(arguments: ["", "12345", "!? 😊", "OK"])
    func ambiguousNonHangulRemainsUntranslated(_ text: String) {
        #expect(NaturalDanmakuLanguageDetector().sourceLanguage(for: text) == nil)
    }

    @Test
    func roomTitleDetectionKeepsItsExistingThreshold() {
        #expect(NaturalRoomTitleLanguageDetector().sourceLanguage(for: "네") == nil)
    }
}
