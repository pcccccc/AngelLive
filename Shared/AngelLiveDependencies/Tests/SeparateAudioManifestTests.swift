#if canImport(KSPlayer)
import AngelLiveCore
import Foundation
import Testing
@testable import AngelLiveDependencies

@Suite("Separate audio combined manifest")
struct SeparateAudioManifestTests {
    @Test("URLs are XML-escaped and files are named by digest")
    func escaping() throws {
        let video = URL(string: "https://media.example.invalid/v.mp4?a=1&b=<2>")!
        let audio = URL(string: "https://media.example.invalid/a.mp4?token='x'")!
        let xml = SeparateAudioManifest.xml(videoURL: video, audioURL: audio)
        #expect(xml.contains("v.mp4?a=1&amp;b=&lt;2&gt;") || xml.contains("v.mp4?a=1&amp;b=%3C2%3E"))
        #expect(xml.contains("a.mp4?token=&apos;x&apos;") || xml.contains("a.mp4?token=%27x%27"))
        #expect(!xml.contains("a=1&b"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try SeparateAudioManifest.write(videoURL: video, audioURL: audio, directory: directory)
        #expect(!file.lastPathComponent.contains("media"))
        #expect(try String(contentsOf: file, encoding: .utf8) == xml)
    }

    @Test("Only identical video and audio requests may share one manifest", arguments: [
        (RoomPlaybackRequestOptions(userAgent: "ua", headers: ["referer": "r"]), true),
        (RoomPlaybackRequestOptions(userAgent: "ua", headers: [:]), false),
        (RoomPlaybackRequestOptions(userAgent: "other", headers: ["Referer": "r"]), false),
        (RoomPlaybackRequestOptions(userAgent: "ua", headers: ["Referer": "x"]), false),
    ])
    func sharedRequest(audio: RoomPlaybackRequestOptions, expected: Bool) {
        let video = RoomPlaybackRequestOptions(userAgent: "ua", headers: ["Referer": "r", "User-Agent": "ua"])
        #expect(KSPlayerSessionConfigurator.sameRequest(video, audio) == expected)
    }
}
#endif
