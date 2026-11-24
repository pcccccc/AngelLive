#if canImport(KSPlayer) && os(macOS)
import AngelLiveCore
import AppKit
import AVFoundation
import Foundation
import KSPlayer
import KSPlayerUI
import Metal
import Testing
@testable import AngelLiveDependencies

@Suite(.serialized)
@MainActor
struct OnDemandPlayerProbeTests {
    private static let fixtureDirectory = ProcessInfo.processInfo.environment["VOD_PROBE_DIRECTORY"]
    private let size = CGSize(width: 320, height: 180)

    @Test func trackNamesLocalizeLanguageCodesAndPreserveTitles() {
        for code in ["chi", "zho", "zh"] {
            #expect(KSOnDemandPlayerController.trackDisplayName(code, language: nil) == "中文")
        }
        for name in ["", "und", "unknown", "ENG"] {
            #expect(KSOnDemandPlayerController.trackDisplayName(name, language: "eng") == "英语")
        }
        for title in ["简体中文", "Fixture"] {
            #expect(KSOnDemandPlayerController.trackDisplayName(title, language: "jpn") == title)
        }
        #expect(KSOnDemandPlayerController.trackDisplayName("jpn", language: nil) == "日语")
    }

    #if DEBUG
    @Test func localMovieReportsPlaybackAcrossPlayAndPause() async throws {
        let files = try await VodDemoMedia.shared.prepare()
        let url = files.directory.appendingPathComponent("sample.mp4")
        let options = KSOptions()
        options.playerTypes = [KSAVPlayer.self]
        options.isAutoPlay = false
        options.registerRemoteControll = false
        let layer = KSPlayerLayer(url: url, options: options)
        let coordinator = KSVideoPlayer.Coordinator(playerLayer: layer)
        let controller = KSOnDemandPlayerController()
        let id = UUID()
        defer { controller.stop() }
        coordinator.onStateChanged = { layer, state in
            controller.synchronize(layer: layer, state: state, playbackID: id)
        }
        controller.attach(coordinator, playbackID: id, url: url, resumePosition: nil, desiredPlayback: true)
        try await waitUntil("Local movie advancing") { (controller.timeSample(for: id)?.current ?? 0) > 0.15 }
        let status = controller.playbackStatus(for: id)
        print("VOD local MP4: layer=\(layer.state), playing=\(status.isPlaying), preparing=\(status.isPreparing)")
        #expect(status.isPlaying)
        #expect(!status.isPreparing)
        #expect(controller.playbackStatus(for: UUID()) == .preparing)
        controller.pause()
        #expect(!controller.playbackStatus(for: id).isPlaying)
        #expect(!controller.playbackStatus(for: id).isPreparing)
        controller.play()
        try await waitUntil("Local movie resumed") { controller.playbackStatus(for: id).isPlaying }
    }
    #endif

    @Test func subtitleOverridesAreClampedAndRestoredAcrossControllers() {
        let original = KSOptions.subtitleFontSize
        let first = KSOnDemandPlayerController()
        let second = KSOnDemandPlayerController()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixture.mkv")
        let firstLayer = makeLayer(url: url)
        let secondLayer = makeLayer(url: url)
        let firstCoordinator = KSVideoPlayer.Coordinator(playerLayer: firstLayer)
        let secondCoordinator = KSVideoPlayer.Coordinator(playerLayer: secondLayer)
        let firstID = UUID()
        let secondID = UUID()
        first.attach(firstCoordinator, playbackID: firstID, url: url, resumePosition: nil, desiredPlayback: false)
        second.attach(secondCoordinator, playbackID: secondID, url: url, resumePosition: nil, desiredPlayback: false)
        defer { first.stop(); second.stop() }
        first.setSubtitleDelay(50)
        #expect(first.subtitleDelay == 10)
        first.setSubtitleDelay(-50)
        #expect(first.subtitleDelay == -10)
        first.setSubtitleFontSizeTier(.small)
        second.setSubtitleFontSizeTier(.large)
        #expect(KSOptions.subtitleFontSize == OnDemandSubtitleFontSizeTier.large.rawValue)
        second.release(secondCoordinator, playbackID: secondID)
        #expect(KSOptions.subtitleFontSize == OnDemandSubtitleFontSizeTier.small.rawValue)
        first.stop()
        #expect(KSOptions.subtitleFontSize == original)
    }

    @Test func externalSubtitlesLoadAndShiftByTheConfiguredDelay() async throws {
        for (format, expected) in [(VodSubtitleFormat.srt, "Fog Harbor"),
                                   (.vtt, "Mountain Letter"), (.ass, "Fog Harbor")] {
            let url = try subtitleURL(format)
            let model = SubtitleModel(url: FileManager.default.temporaryDirectory.appendingPathComponent("fixture.mkv"))
            let info = URLSubtitleInfo(subtitleID: "ext:\(format.rawValue)", name: "Fixture",
                                       url: url, userAgent: "fixture-agent", languageCode: "en")
            func cue() -> String? {
                model.parts.first?.text?.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            model.addSubtitle(info: info)
            model.selectedSubtitleInfo = info
            try await waitUntil("Subtitle cue \(format.rawValue)") {
                model.subtitle(currentTime: 1.25, playRatio: 16.0 / 9, screenSize: size)
                return cue() == expected
            }
            let part = try #require(model.parts.first)
            #expect(part.start == 1 && part.end == 2)
            if format == .ass {
                let text = try #require(part.text)
                let color = try #require(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
                let rgb = try #require(color.usingColorSpace(.deviceRGB))
                #expect(rgb.redComponent > 0.95 && rgb.greenComponent < 0.05 && rgb.blueComponent < 0.05)
                #expect(part.render.right?.position?.verticalAlign == .top)
                print("VOD probe ASS text parser: cue and red foreground; top alignment; vertical margin \(part.render.right?.position?.verticalMargin ?? -1)")
            }
            model.subtitleDelay = 0.5
            model.cleanParts()
            #expect(model.parts.isEmpty)
            model.subtitle(currentTime: 1.25, playRatio: 16.0 / 9, screenSize: size)
            #expect(model.parts.isEmpty)
            model.subtitle(currentTime: 1.75, playRatio: 16.0 / 9, screenSize: size)
            #expect(cue() == expected)
            model.subtitleDelay = -0.5
            model.cleanParts()
            model.subtitle(currentTime: 0.75, playRatio: 16.0 / 9, screenSize: size)
            #expect(cue() == expected)
            print("VOD probe \(format.rawValue): cue 1.0...2.0 s, ±0.5 s offset")
        }
    }

    @Test func alternateASSRendererReportsPositionedColorLayers() async throws {
        let original = KSOptions.isASSUseImageRender
        KSOptions.isASSUseImageRender = true
        defer { KSOptions.isASSUseImageRender = original }
        let url = try subtitleURL(.ass)
        let model = SubtitleModel(url: FileManager.default.temporaryDirectory.appendingPathComponent("fixture.mkv"))
        let info = URLSubtitleInfo(url: url)
        model.selectedSubtitleInfo = info
        try await waitUntil("ASS bitmap cue") {
            model.subtitle(currentTime: 1.25, playRatio: 16.0 / 9, screenSize: size)
            return model.parts.first?.render.left != nil
        }
        let image = try #require(model.parts.first?.render.left)
        guard case let .assBlend(layers, bounds) = image.source else {
            Issue.record("Expected positioned ASS layers")
            return
        }
        let x = bounds.minX * size.width / image.displaySize.width
        let y = bounds.minY * size.height / image.displaySize.height
        #expect(x >= 60 && x <= 70)
        #expect(y >= 50 && y < 82)
        #expect(layers.contains { $0.color & 0xFFFFFF00 == 0xFF000000 })
        #expect(layers.contains { $0.color & 0xFFFFFF00 == 0 })
        print("VOD probe ASS bitmap parser: \(layers.count) layers; bounds \(bounds)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOD_PROBE_DIRECTORY"] != nil))
    func hdr10WithEmbeddedASSAndTwoAudioTracksUsesTheRealController() async throws {
        let url = try fixture("hdr10.mkv")
        let layer = makeLayer(url: url)
        let controller = KSOnDemandPlayerController()
        let id = UUID()
        let originalSize = KSOptions.subtitleFontSize
        let coordinator = KSVideoPlayer.Coordinator(playerLayer: layer)
        coordinator.onStateChanged = { playerLayer, state in
            controller.synchronize(layer: playerLayer, state: state, playbackID: id)
        }
        defer { controller.stop() }
        let external = try [VodSubtitleFormat.srt, .vtt, .ass].map {
            try VodExternalSubtitle(subtitleID: $0.rawValue, name: $0.rawValue, format: $0, url: subtitleURL($0))
        }
        controller.attach(coordinator, playbackID: id, url: url, subtitles: external + [external[0]],
                          userAgent: "fixture-agent", resumePosition: nil, desiredPlayback: false)
        try await waitUntil("HDR10 player readiness") { layer.player.isReadyToPlay && layer.player.loadState == .playable }
        controller.refreshTracks()
        #expect(controller.subtitleTracks.filter(\.isExternal).map(\.id) == ["ext:srt", "ext:vtt", "ext:ass"])
        #expect(controller.subtitleTracks.contains { !$0.isExternal })
        #expect(controller.audioTracks.count == 2)
        #expect(layer.options.dynamicRange == .hdr10)
        let audio = layer.player.tracks(mediaType: .audio)
        let channelCounts = audio.compactMap {
            $0.formatDescription.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
        }
        #expect(channelCounts == [1, 6])
        let other = try #require(controller.audioTracks.first { $0.id != controller.selectedAudioTrackID })
        controller.selectAudioTrack(id: other.id)
        try await waitUntil("Second audio track selected") {
            controller.refreshTracks()
            return controller.selectedAudioTrackID == other.id
        }
        controller.selectSubtitle(id: "ext:srt")
        #expect(layer.subtitleModel.selectedSubtitleInfo?.subtitleID == "ext:srt")
        controller.selectSubtitle(id: nil)
        #expect(controller.selectedSubtitleID == nil && layer.subtitleModel.selectedSubtitleInfo == nil)
        controller.adjustSubtitleDelay(by: 0.5)
        #expect(controller.subtitleDelay == 0.5 && layer.subtitleModel.subtitleDelay == 0.5)
        controller.adjustSubtitleDelay(by: 20)
        #expect(controller.subtitleDelay == 10)
        controller.setSubtitleDelay(-20)
        #expect(layer.subtitleModel.subtitleDelay == -10)
        controller.resetSubtitleDelay()
        #expect(layer.subtitleModel.subtitleDelay == 0)
        for tier in OnDemandSubtitleFontSizeTier.allCases {
            controller.setSubtitleFontSizeTier(tier)
            #expect(KSOptions.subtitleFontSize == tier.rawValue)
        }
        controller.play()
        try await waitUntil("Playback before seeking") { controller.timeSample(for: id)?.current ?? 0 > 0.15 }
        controller.pause()
        #expect(await controller.seek(to: 0.5, playbackID: id))
        #expect(abs(layer.player.currentPlaybackTime - 0.5) <= 0.08)
        #expect(await controller.seek(to: 0, playbackID: id))
        #expect(abs(layer.player.currentPlaybackTime) <= 0.08)
        controller.play()
        try await waitUntil("Playback after seeking to zero") { controller.timeSample(for: id)?.current ?? 0 > 0.15 }
        let frame = try await decodedFrame(from: layer)
        #expect(frame.width == 320 && frame.height == 180)
        print("VOD probe HDR10: \(layer.options.dynamicRange); audio channel counts \(channelCounts); decoded \(frame.width)x\(frame.height)")
        controller.release(coordinator, playbackID: UUID())
        #expect(controller.playbackID == id)
        controller.stop()
        #expect(KSOptions.subtitleFontSize == originalSize)
        #expect(controller.playbackID == nil && controller.audioTracks.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOD_PROBE_DIRECTORY"] != nil))
    func controllerHoldsPlaybackWhileRestoringProgress() async throws {
        let url = try fixture("hdr10.mkv")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VodProgressStore(directory: folder)
        let detail = try VodCatalog.detail(
            from: Data(#"{"kind":"movie","title":"雾港回声","episodes":[{"id":"episode-a","number":1,"title":"雾港回声"}]}"#.utf8),
            pluginID: "fixture.plugin", workID: "work-a"
        )
        let episode = try #require(detail.episodes.first)
        try store.updateEpisode(.init(position: 1, duration: 4, completed: false, updatedAt: .now),
                                episodeID: episode.id, for: VodProgressKey(pluginID: detail.pluginID, workID: detail.workID))
        let model = VodPlaybackModel(
            dependencies: .init(loadDetail: { detail }, resolvePlayback: { detail, episode, _ in
                try VodCatalog.playback(from: Data(#"{"url":"\#(url.absoluteString)","isLive":false}"#.utf8),
                                        workID: detail.workID, episode: episode, liveType: "fixture.plugin")
            }),
            progressStore: store
        )
        await model.loadDetail()
        await model.selectEpisode(id: episode.id)
        let playback = try #require(model.playback)
        #expect(playback.resumePosition == 1)
        let layer = makeLayer(url: url)
        let coordinator = KSVideoPlayer.Coordinator(playerLayer: layer)
        let controller = KSOnDemandPlayerController()
        defer { controller.stop() }
        coordinator.onStateChanged = { playerLayer, state in
            controller.synchronize(layer: playerLayer, state: state, playbackID: playback.id)
        }
        controller.attach(coordinator, playbackID: playback.id, url: url,
                          resumePosition: playback.resumePosition, desiredPlayback: true)
        try await waitUntil("Player ready for restoration") {
            layer.player.isReadyToPlay && layer.player.loadState == .playable
        }
        #expect(controller.isRestoring(for: playback.id))
        #expect(controller.playbackStatus(for: playback.id) == .preparing)
        #expect(!layer.player.isPlaying && controller.timeSample(for: playback.id) == nil)
        var onReady = false
        controller.restoreIfPossible(model: model) { id in
            onReady = id == playback.id
            #expect(!layer.player.isPlaying)
        }
        try await waitUntil("Restored playback advancing") {
            onReady && (controller.timeSample(for: playback.id)?.current ?? 0) >= 1
        }
        #expect(!controller.isRestoring(for: playback.id))
        #expect(model.progressSnapshot?.episodes[episode.id]?.position == 1)
        print("VOD probe restore: paused through the confirmed seek; playback resumed from 1.0 s")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOD_PROBE_DIRECTORY"] != nil))
    func dolbyVisionProfileEightIsDetectedAndDecodesAFrame() async throws {
        let url = try fixture("dolby.mp4")
        let layer = makeLayer(url: url)
        let coordinator = KSVideoPlayer.Coordinator(playerLayer: layer)
        let controller = KSOnDemandPlayerController()
        let id = UUID()
        defer { controller.stop() }
        coordinator.onStateChanged = { playerLayer, state in
            controller.synchronize(layer: playerLayer, state: state, playbackID: id)
        }
        controller.attach(coordinator, playbackID: id, url: url, resumePosition: nil, desiredPlayback: true)
        try await waitUntil("Dolby Vision playback advancing") { controller.timeSample(for: id)?.current ?? 0 > 0.15 }
        let track = try #require(layer.player.tracks(mediaType: .video).first)
        #expect(track.dynamicRange == .dolbyVision)
        #expect(layer.options.dynamicRange == .dolbyVision)
        let frame = try await decodedFrame(from: layer)
        #expect(frame.width == 320 && frame.height == 180)
        print("VOD probe Dolby Vision: \(layer.options.dynamicRange); decoded \(frame.width)x\(frame.height)")
    }

    private func subtitleURL(_ format: VodSubtitleFormat) throws -> URL {
        try #require(Bundle.module.url(forResource: "vod-cue", withExtension: format.rawValue))
    }

    private func fixture(_ name: String) throws -> URL {
        let root = try #require(Self.fixtureDirectory)
        let url = URL(fileURLWithPath: root).appendingPathComponent(name)
        try #require(FileManager.default.fileExists(atPath: url.path), "Missing generated fixture \(name)")
        return url
    }

    private func makeLayer(url: URL) -> KSPlayerLayer {
        let options = KSOptions()
        options.playerTypes = [KSMEPlayer.self]
        options.isAutoPlay = false
        options.isLoopPlay = false
        options.videoDecodeType = .software
        options.renderUseDispatchSourceTimer = true
        options.registerRemoteControll = false
        options.automaticWindowResize = false
        options.preferredForwardBufferDuration = 0
        let layer = KSPlayerLayer(url: url, options: options)
        layer.player.view.frame = CGRect(origin: .zero, size: size)
        return layer
    }

    private func decodedFrame(from layer: KSPlayerLayer) async throws -> CGImage {
        var frame: CGImage?
        try await waitUntil("Decoded video frame") {
            frame = await layer.player.thumbnailImageAtCurrentTime()
            return frame != nil
        }
        return try #require(frame)
    }

    private func waitUntil(_ description: String, condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(await condition(), "\(description) timed out")
    }
}
#endif
