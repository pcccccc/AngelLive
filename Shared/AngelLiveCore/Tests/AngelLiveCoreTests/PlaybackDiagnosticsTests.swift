import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Playback diagnostics")
@MainActor
struct PlaybackDiagnosticsTests {
    @Test func boundedLogExportsTypedEventsAcrossSessions() throws {
        let log = PlaybackEventLog(capacity: 3)
        let first = UUID(), second = UUID()
        log.record(.sessionStarted, sessionID: first, elapsed: 0)
        log.record(.sourceAssigned(line: 0, quality: 1), sessionID: first, elapsed: 1)
        log.record(.sessionStarted, sessionID: second, elapsed: 0)
        log.record(.recovery(action: .switchCDN, attempt: 2, limit: 3), sessionID: second, elapsed: 2)
        #expect(log.entries.count == 3)
        #expect(log.entries.first?.event == .sourceAssigned(line: 0, quality: 1))
        #expect(Set(log.entries.map(\.sessionID)) == [first, second])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([PlaybackEventEntry].self, from: log.exportJSON())
        #expect(decoded.map(\.event) == log.entries.map(\.event))
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test func invalidEngineNumbersDoNotBreakExport() throws {
        let log = PlaybackEventLog()
        let session = UUID()
        log.record(.sample(bytesRead: 0, playhead: .nan, buffered: 0), sessionID: session, elapsed: 1)
        log.record(.startupCompleted(milliseconds: .infinity), sessionID: session, elapsed: 1)
        log.record(.sessionStarted, sessionID: session, elapsed: .infinity)
        #expect(log.entries.isEmpty)
        #expect(try JSONSerialization.jsonObject(with: log.exportJSON()) as? [Any] != nil)
    }

    @Test func readinessAloneDoesNotFinishStartupAndProgressFinishesOnce() throws {
        let log = PlaybackEventLog()
        var now: TimeInterval = 10
        var outcomes: [CDNStartupOutcome] = []
        let session = PlaybackDiagnosticsSession(clock: { now }, log: log,
            isLoggingEnabled: { true }, finishStartup: { outcomes.append($0) })
        session.fetchingSource()
        #expect(session.startupStage == .fetchingSource)
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "private-line-marker", line: 1, quality: 0)
        #expect(session.startupStage == .connecting)
        session.engineStateChanged(.readyToPlay, isPlaying: true)
        #expect(outcomes.isEmpty)
        #expect(!session.hasStartedPlayback)
        session.observe(.sample(.init(bytesRead: 1024, playhead: 0, buffered: 1, isPlaying: false)))
        #expect(session.startupStage == .buffering)
        now = 12
        session.observe(.sample(.init(bytesRead: 2048, playhead: 1, buffered: 1, isPlaying: true)))
        session.observe(.sample(.init(bytesRead: 4096, playhead: 2, buffered: 1, isPlaying: true)))
        session.engineStateChanged(.error, isPlaying: false)
        #expect(outcomes.count == 1)
        #expect(session.hasStartedPlayback)
        #expect(outcomes.first?.result == .success(milliseconds: 2_000))
        let export = String(decoding: try log.exportJSON(), as: UTF8.self)
        #expect(!export.contains("private-line-marker"))
        #expect(!export.contains("fixture.plugin"))
    }

    @Test func oldPlayerProgressBeforeSourceAssignmentDoesNotFinishNewSession() {
        let session = PlaybackDiagnosticsSession(isLoggingEnabled: { false }, finishStartup: { _ in })
        session.fetchingSource()
        session.observe(.sample(.init(bytesRead: 100, playhead: 8, buffered: 1, isPlaying: true)))
        session.observe(.sample(.init(bytesRead: 200, playhead: 9, buffered: 1, isPlaying: true)))
        #expect(!session.hasStartedPlayback)
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-a", line: 0, quality: 0)
        session.observe(.sample(.init(bytesRead: 300, playhead: 0, buffered: 1, isPlaying: true)))
        #expect(!session.hasStartedPlayback)
        session.observe(.sample(.init(bytesRead: 400, playhead: 1, buffered: 1, isPlaying: true)))
        #expect(session.hasStartedPlayback)
    }

    @Test func developerModeOnlyGatesLoggingNotLearning() {
        let log = PlaybackEventLog()
        var outcomes: [CDNStartupOutcome] = []
        let session = PlaybackDiagnosticsSession(log: log, isLoggingEnabled: { false },
            finishStartup: { outcomes.append($0) })
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-a", line: 0, quality: 0)
        session.observe(.sample(.init(bytesRead: 0, playhead: 0, buffered: 0, isPlaying: true)))
        session.observe(.sample(.init(bytesRead: 0, playhead: 1, buffered: 0, isPlaying: true)))
        #expect(outcomes.count == 1)
        #expect(log.entries.isEmpty)
    }

    @Test func interruptedAndReplacedAttemptsAreNotFailures() {
        var outcomes: [CDNStartupOutcome] = []
        let session = PlaybackDiagnosticsSession(isLoggingEnabled: { false },
            finishStartup: { outcomes.append($0) })
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-a", line: 0, quality: 0)
        session.interruptStartup()
        session.engineStateChanged(.error, isPlaying: false)
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-b", line: 1, quality: 0)
        session.engineStateChanged(.paused, isPlaying: false)
        session.observe(.recovering(action: .reloadPlayArgs, attempt: 1, limit: 3, startupFailure: .timeout))
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-c", line: 2, quality: 0)
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-d", line: 3, quality: 0)
        session.end()
        session.engineStateChanged(.error, isPlaying: false)
        #expect(outcomes.isEmpty)
    }

    @Test func resumedProgressUnblocksPresentationWithoutLearningInterruptedAttempt() {
        var outcomes: [CDNStartupOutcome] = []
        let session = PlaybackDiagnosticsSession(isLoggingEnabled: { false },
            finishStartup: { outcomes.append($0) })
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-a", line: 0, quality: 0)
        session.engineStateChanged(.paused, isPlaying: false)
        session.observe(.sample(.init(bytesRead: 0, playhead: 0, buffered: 0, isPlaying: true)))
        #expect(!session.hasStartedPlayback)
        session.observe(.sample(.init(bytesRead: 0, playhead: 1, buffered: 0, isPlaying: true)))
        #expect(session.hasStartedPlayback)
        #expect(outcomes.isEmpty)
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-b", line: 1, quality: 0)
        #expect(session.hasStartedPlayback)
    }

    @Test func recoveryFinishesFailedAttemptOnceAndKeepsLogicalSession() {
        let log = PlaybackEventLog()
        var outcomes: [CDNStartupOutcome] = []
        let session = PlaybackDiagnosticsSession(log: log, isLoggingEnabled: { true },
            finishStartup: { outcomes.append($0) })
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-a", line: 0, quality: 0)
        session.observe(.recovering(action: .reloadPlayArgs, attempt: 1, limit: 3, startupFailure: .timeout))
        let notice = session.recoveryNotice?.id
        session.engineStateChanged(.error, isPlaying: false)
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.result == .failure)
        session.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-a", line: 0, quality: 0)
        session.observe(.recovering(action: .reloadPlayArgs, attempt: 2, limit: 3, startupFailure: .timeout))
        #expect(session.recoveryNotice?.id != notice)
        #expect(session.recoveryNotice?.title == "正在重新获取播放地址（2/3）")
        #expect(outcomes.count == 2)
        #expect(Set(log.entries.map(\.sessionID)).count == 1)
        #expect(log.entries.filter { $0.event == .sessionStarted }.count == 1)
    }

    @Test func engineStateDeduplicationAndEndAreIdempotent() {
        let log = PlaybackEventLog()
        let session = PlaybackDiagnosticsSession(log: log, isLoggingEnabled: { true }, finishStartup: { _ in })
        session.fetchingSource()
        session.engineStateChanged(.preparing, isPlaying: false)
        session.engineStateChanged(.preparing, isPlaying: false)
        session.end()
        session.end()
        session.engineStateChanged(.bufferFinished, isPlaying: true)
        #expect(log.entries.map(\.event) == [.sessionStarted,
            .engineStateChanged(state: .preparing, isPlaying: false), .sessionEnded])
    }

    @Test func coordinatorReportsEachRecoveryBeforeExecutingItAndExhaustsOnce() {
        let log = PlaybackEventLog()
        let diagnostics = PlaybackDiagnosticsSession(log: log, isLoggingEnabled: { true }, finishStartup: { _ in })
        diagnostics.sourceAssigned(pluginID: "fixture.plugin", lineID: "line-a", line: 0, quality: 0)
        var actions: [RecoveryActionKind] = []
        func performed(_ action: RecoveryActionKind) {
            #expect(diagnostics.recoveryNotice?.action == action)
            actions.append(action)
        }
        let coordinator = PlaybackRecoveryCoordinator(
            config: .init(startupTimeout: 1, stallMonitoringEnabled: true),
            actions: .init(refreshSameURL: { performed(.refreshSameURL) },
                           switchCDN: { performed(.switchCDN) },
                           reloadPlayArgs: { performed(.reloadPlayArgs) }, reportFailed: { _ in }),
            sample: { nil }, observation: { diagnostics.observe($0) })
        coordinator.episodeChanged(streamKey: "fixture.session")
        for _ in 0..<5 {
            coordinator.advance(.tick(sample: .init(bytesRead: 0, playhead: 0, buffered: 0, isPlaying: false), delta: 1))
        }
        #expect(actions == [.reloadPlayArgs, .switchCDN, .refreshSameURL])
        #expect(log.entries.filter { $0.event == .recoveryExhausted }.count == 1)
        #expect(log.entries.filter {
            if case .sample = $0.event { return true }; return false
        }.count == 4)
    }
}

@Suite("CDN preference learning")
struct CDNPreferenceTests {
    private func makeStore(_ suite: String) -> CDNPreferenceStore {
        CDNPreferenceStore(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func insufficientSamplesPreservePluginOrder() async {
        let suite = "fixture.cdn.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = makeStore(suite)
        for _ in 0..<3 {
            await store.recordSuccess(lineID: "line-b", pluginID: "fixture.plugin", startupMilliseconds: 500)
        }
        #expect(await store.preferredIndex(lineIDs: ["line-a", "line-b"], pluginID: "fixture.plugin") == nil)
        #expect(await store.preferredIndex(lineIDs: [""], pluginID: "fixture.plugin") == nil)
    }

    @Test func rankingNamespaceExpiryAndPersistence() async throws {
        let suite = "fixture.cdn.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = makeStore(suite)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<3 {
            await store.recordFailure(lineID: "line-a", pluginID: "fixture.plugin", now: now)
            await store.recordSuccess(lineID: "line-b", pluginID: "fixture.plugin", startupMilliseconds: 500, now: now)
        }
        #expect(await store.preferredIndex(lineIDs: ["line-a", "line-b"], pluginID: "fixture.plugin", now: now) == 1)
        #expect(await store.preferredIndex(lineIDs: ["line-a", "line-b"], pluginID: "fixture.other", now: now) == nil)
        let restored = makeStore(suite)
        #expect(await restored.preferredIndex(lineIDs: ["line-a", "line-b"], pluginID: "fixture.plugin", now: now) == 1)
        let data = try #require(UserDefaults(suiteName: suite)?.data(forKey: "AngelLive.Playback.CDNObservations.v1"))
        let stored = String(decoding: data, as: UTF8.self)
        #expect(!stored.contains("fixture.plugin"))
        #expect(!stored.contains("line-a"))
        let expired = now.addingTimeInterval(7 * 24 * 60 * 60)
        #expect(await restored.preferredIndex(lineIDs: ["line-a", "line-b"], pluginID: "fixture.plugin", now: expired) == nil)
    }

    @Test func tiesAndDuplicateLinesKeepFirstIndex() async {
        let suite = "fixture.cdn.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = makeStore(suite)
        for _ in 0..<3 {
            for line in ["line-a", "line-b"] {
                await store.recordSuccess(lineID: line, pluginID: "fixture.plugin", startupMilliseconds: 500)
            }
        }
        #expect(await store.preferredIndex(lineIDs: ["line-a", "line-b"], pluginID: "fixture.plugin") == 0)
        #expect(await store.preferredIndex(lineIDs: ["line-b", "line-b"], pluginID: "fixture.plugin") == 0)
    }
}
