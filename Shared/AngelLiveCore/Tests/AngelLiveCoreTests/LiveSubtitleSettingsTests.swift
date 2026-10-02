import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Live subtitle preferences")
struct LiveSubtitleSettingsTests {
    @Test @MainActor
    func subtitlePreferencesSurviveReopeningWithoutEnablingOtherTranslation() throws {
        let suite = "fixture.subtitle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = LiveSubtitleSettings(defaults: defaults)
        #expect(!settings.isEnabled)
        settings.isEnabled = true
        settings.sourceLanguage = .korean

        let reopened = LiveSubtitleSettings(defaults: defaults)
        #expect(reopened.isEnabled)
        #expect(reopened.sourceLanguage == .korean)
        #expect(!defaults.bool(forKey: "roomTranslation.enabled"))
        #expect(!defaults.bool(forKey: "roomTranslation.danmakuEnabled"))

        reopened.isEnabled = false
        let disabled = LiveSubtitleSettings(defaults: defaults)
        #expect(!disabled.isEnabled)
        #expect(disabled.sourceLanguage == .korean)
    }
}
