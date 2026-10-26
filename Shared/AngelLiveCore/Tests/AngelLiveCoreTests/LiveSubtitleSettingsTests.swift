import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Live subtitle preferences")
struct LiveSubtitleSettingsTests {
    @Test @MainActor
    func languagePreferenceSurvivesReopeningWithoutStartingAnyTranslation() throws {
        let suite = "fixture.subtitle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = LiveSubtitleSettings(defaults: defaults)
        settings.sourceLanguage = .korean

        let reopened = LiveSubtitleSettings(defaults: defaults)
        #expect(reopened.sourceLanguage == .korean)
        #expect(!defaults.bool(forKey: "roomTranslation.enabled"))
        #expect(!defaults.bool(forKey: "roomTranslation.danmakuEnabled"))

        let room = LiveSubtitlePlaybackState()
        #expect(!room.isEnabled)
        #expect(room.sourceLanguage == nil)
    }

    @Test @MainActor
    func legacyGlobalEnableDoesNotStartANewRoom() throws {
        let suite = "fixture.subtitle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "liveSubtitle.enabled")
        defaults.set(LiveSubtitleLanguage.japanese.rawValue, forKey: "liveSubtitle.sourceLanguage")

        let settings = LiveSubtitleSettings(defaults: defaults)
        #expect(settings.sourceLanguage == .japanese)
        let room = LiveSubtitlePlaybackState()
        #expect(!room.isEnabled)
        #expect(room.sourceLanguage == nil)
    }

    @Test @MainActor
    func enablingStartsDetectionOnlyInThisPlayerAndIgnoresResourcePreference() throws {
        let suite = "fixture.subtitle.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LiveSubtitleSettings(defaults: defaults)
        let firstWindow = LiveSubtitlePlaybackState()
        let secondWindow = LiveSubtitlePlaybackState()

        #expect(firstWindow.startAutomatically(activationID: firstWindow.activationID))
        #expect(firstWindow.isEnabled)
        #expect(firstWindow.phase == .preparing)
        #expect(firstWindow.sourceLanguage == nil)
        #expect(!secondWindow.isEnabled)
        settings.sourceLanguage = .korean
        #expect(firstWindow.sourceLanguage == nil)
        #expect(secondWindow.sourceLanguage == nil)

        #expect(secondWindow.startAutomatically(activationID: secondWindow.activationID))
        #expect(secondWindow.apply(.init(phase: .transcribing, sourceLanguage: "ja"), activationID: secondWindow.activationID))
        firstWindow.stop()
        #expect(!firstWindow.isEnabled)
        #expect(secondWindow.sourceLanguage == "ja")
    }

    @Test @MainActor
    func leavingRoomInvalidatesDetectionAndAnUnconfirmedLanguageAction() {
        let room = LiveSubtitlePlaybackState()
        #expect(room.startAutomatically(activationID: room.activationID))
        let oldAction = room.activationID
        #expect(room.apply(.init(phase: .manualSelectionRequired), activationID: oldAction))
        room.stop()

        #expect(room.sourceLanguage == nil)
        #expect(!room.chooseLanguage("ko", activationID: oldAction))
        #expect(!room.apply(.init(phase: .transcribing, sourceLanguage: "en"), activationID: oldAction))
        #expect(!room.isEnabled)
        #expect(room.startAutomatically(activationID: room.activationID))
        #expect(room.sourceLanguage == nil)
    }

    @Test @MainActor
    func manualLanguageRequiresUncertainSpeechAndInvalidatesEarlierDetection() {
        let room = LiveSubtitlePlaybackState()
        #expect(!room.chooseLanguage("fr", activationID: room.activationID))
        #expect(room.startAutomatically(activationID: room.activationID))
        let attempt = room.activationID
        #expect(!room.chooseLanguage("fr", activationID: attempt))
        #expect(room.apply(.init(phase: .waitingForSpeech), activationID: attempt))
        #expect(!room.chooseLanguage("fr", activationID: attempt))
        #expect(room.apply(.init(phase: .manualSelectionRequired), activationID: attempt))
        #expect(room.chooseLanguage("fr", activationID: attempt))
        #expect(room.sourceLanguage == "fr")
        #expect(room.phase == .preparing)
        #expect(room.activationID != attempt)
        #expect(!room.apply(.init(phase: .transcribing, sourceLanguage: "en"), activationID: attempt))
        #expect(!room.chooseLanguage("de", activationID: attempt))
    }

    @Test @MainActor
    func detectingAnyLanguageDoesNotRestartThePlaybackAttempt() {
        let room = LiveSubtitlePlaybackState()
        #expect(room.startAutomatically(activationID: room.activationID))
        let attempt = room.activationID
        #expect(room.apply(.init(phase: .transcribing, sourceLanguage: "es"), activationID: attempt))
        #expect(room.sourceLanguage == "es")
        #expect(room.activationID == attempt)
        #expect(room.resourcePreparation == nil)
    }

    @Test @MainActor
    func retryStartsFreshDetectionOnlyAfterATransientFailure() {
        let room = LiveSubtitlePlaybackState()
        #expect(room.startAutomatically(activationID: room.activationID))
        let attempt = room.activationID
        #expect(!room.startAutomatically(activationID: attempt))
        #expect(room.apply(.init(phase: .failed, sourceLanguage: "es", message: "fixture failure"), activationID: attempt))
        #expect(room.startAutomatically(activationID: attempt))
        #expect(room.isEnabled)
        #expect(room.phase == .preparing)
        #expect(room.sourceLanguage == nil)
        #expect(room.activationID != attempt)
        #expect(!room.apply(.init(phase: .transcribing, sourceLanguage: "es"), activationID: attempt))
    }

    @Test @MainActor
    func downloadAuthorizationIsExplicitAndLimitedToTheCurrentResource() {
        let room = LiveSubtitlePlaybackState()
        #expect(room.startAutomatically(activationID: room.activationID))
        let detection = room.activationID
        #expect(!room.prepareResources(activationID: detection))
        #expect(room.apply(.init(phase: .modelDownloadRequired), activationID: detection))
        #expect(room.resourcePreparation == nil)
        #expect(room.prepareResources(activationID: detection))
        #expect(room.resourcePreparation == .languageDetection)
        #expect(room.activationID != detection)
        #expect(!room.apply(.init(phase: .failed), activationID: detection))

        let modelDownload = room.activationID
        #expect(room.apply(.init(phase: .speechResourcesRequired, sourceLanguage: "de"), activationID: modelDownload))
        #expect(room.prepareResources(activationID: modelDownload))
        #expect(room.resourcePreparation == .speech(language: "de"))
        #expect(room.sourceLanguage == "de")
        let speechDownload = room.activationID
        room.stop()
        #expect(!room.prepareResources(activationID: speechDownload))
        #expect(!room.apply(.init(phase: .transcribing, sourceLanguage: "de"), activationID: speechDownload))
        #expect(room.resourcePreparation == nil)
    }
}
