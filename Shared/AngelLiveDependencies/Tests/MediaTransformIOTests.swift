import Foundation
import Testing
@testable import AngelLiveDependencies
#if canImport(KSPlayer)
import AngelLiveCore
import KSPlayer
import Libavformat
#endif

struct MediaTransformIOTests {
    @Test func classifiesByTagsAndResolvesRelativeURLs() throws {
        let base = try #require(URL(string: "https://media.example.invalid/moved/master?token=fixture"))
        let text = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="main, stereo",URI="audio/list"
        #EXT-X-STREAM-INF:BANDWIDTH=100000
        ../video/list?variant=1
        #EXTINF:2,
        https://cdn.example.invalid/object?id=1
        #EXTINF:2,
        chunk-without-extension
        """
        let playlist = try MediaTransformPlaylist(data: Data(text.utf8), baseURL: base)
        #expect(playlist.references[URL(string: "https://media.example.invalid/moved/audio/list")!] == .playlist)
        #expect(playlist.references[URL(string: "https://media.example.invalid/video/list?variant=1")!] == .playlist)
        #expect(playlist.references[URL(string: "https://cdn.example.invalid/object?id=1")!] == .segment)
        #expect(playlist.references[URL(string: "https://media.example.invalid/moved/chunk-without-extension")!] == .segment)
    }

    @Test(arguments: [
        "#EXT-X-MAP:URI=\"init\"", "#EXT-X-BYTERANGE:188@0", "#EXT-X-PART:DURATION=0.5,URI=\"part\"",
        "#EXT-X-KEY:METHOD=AES-128,URI=\"key\"", "#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES,URI=\"key\"",
        "#EXT-X-DEFINE:NAME=\"name\",VALUE=\"value\""
    ])
    func rejectsUnsupportedFeaturesBeforeAnySegmentIsOpened(tag: String) throws {
        let base = try #require(URL(string: "https://media.example.invalid/list"))
        let bytes = Data("#EXTM3U\n#EXTINF:2,\nchunk\n\(tag)\n".utf8)
        #expect(throws: MediaTransformIOError.self) {
            try MediaTransformPlaylist(data: bytes, baseURL: base)
        }
    }

    @Test func rejectsAmbiguousOrUnclassifiedReferences() throws {
        let base = try #require(URL(string: "https://media.example.invalid/list"))
        for body in ["chunk", "#EXTINF:2,", "#EXT-X-STREAM-INF:BANDWIDTH=1\nshared\n#EXTINF:2,\nshared"] {
            #expect(throws: MediaTransformIOError.self) {
                try MediaTransformPlaylist(data: Data("#EXTM3U\n\(body)".utf8), baseURL: base)
            }
        }
    }

    #if canImport(KSPlayer)
    @Test func transportFailureCanRecoverWithoutClearingPermanentFailure() {
        let state = MediaTransformFailureState()
        state.record(MediaTransformIOError.ffmpeg(operation: "request", code: -60))
        #expect(state.failure != nil)
        #expect(!state.hasFatalFailure)
        state.didRead()
        #expect(state.failure == nil)
        state.record(MediaTransformIOError.unsupportedMediaContainer)
        state.record(MediaTransformIOError.ffmpeg(operation: "request", code: -5))
        state.didRead()
        #expect(state.hasFatalFailure)
        #expect(state.failure is MediaTransformIOError)
    }

    @Test func lateInvalidSegmentRemainsAnExplicitFailureAfterHLSEOF() throws {
        let transform = try Self.transform()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try #require(Bundle.module.url(forResource: "media-transform-plain-0.ts", withExtension: nil))
        var encoded = [UInt8](try Data(contentsOf: source))
        try transform.apply(to: &encoded, at: 0)
        let segment = directory.appendingPathComponent("segment.bin")
        try Data(encoded).write(to: segment)
        let playlist = directory.appendingPathComponent("playlist.m3u8")
        try Data("#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXTINF:0.5,\nsegment.bin\n#EXT-X-ENDLIST\n".utf8).write(to: playlist)
        let context = try MediaTransformContextFactory.make(url: playlist, options: KSOptions(),
                                                           transform: transform, interrupt: IOInterruptContext())
        defer { context.close() }
        for track in context.assetTracks { track.isEnabled = true }
        let failure = MediaTransformContextFactory.failureReader(for: context)
        #expect(failure() == nil)
        var packetCount = 0
        while context.read() != nil { packetCount += 1 }
        #expect(packetCount > 0)

        // Change the next network/resource open only after make/probe succeeded.
        var invalid = [UInt8](repeating: 0x41, count: 600)
        try transform.apply(to: &invalid, at: 0)
        try Data(invalid).write(to: segment)
        #expect(context.performSeek(time: 0, flags: AVSEEK_FLAG_BACKWARD) >= 0)
        while context.read() != nil {}
        guard let error = failure() as? MediaTransformIOError, case .unsupportedMediaContainer = error else {
            Issue.record("A late invalid TS segment must survive HLS's conversion of read failure into EOF")
            return
        }
    }

    @Test func transformsAcrossShortReadsAndSeekAndClosesIdempotently() throws {
        let transform = try Self.transform()
        var plaintext = (0..<(188 * 5 + 71)).map { UInt8(truncatingIfNeeded: $0) }
        for offset in stride(from: 0, to: plaintext.count, by: 188) { plaintext[offset] = 0x47 }
        var encoded = plaintext
        try transform.apply(to: &encoded, at: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(encoded).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var native: UnsafeMutablePointer<AVIOContext>?
        #expect(avio_open2(&native, url.path, AVIO_FLAG_READ, nil, nil) == 0)
        let input = MediaTransformInput(native: try #require(native), playlist: nil, transform: transform)
        defer { input.close() }
        #expect(input.fileSize() == plaintext.count)
        var actual: [UInt8] = []
        for size in [1, 2, 5, 183, 17, 400, 1200] {
            var bytes = [UInt8](repeating: 0, count: size)
            let count = input.read(buffer: &bytes, size: Int32(size))
            if count > 0 { actual.append(contentsOf: bytes.prefix(Int(count))) }
        }
        var tail = [UInt8](repeating: 0, count: 2048)
        while true {
            let count = input.read(buffer: &tail, size: Int32(tail.count))
            if count < 0 { break }
            actual.append(contentsOf: tail.prefix(Int(count)))
        }
        #expect(actual == plaintext)
        #expect(input.seek(offset: 0, whence: SEEK_SET) == 0)
        var one: UInt8 = 0
        #expect(input.read(buffer: &one, size: 1) == 1)
        #expect(input.seek(offset: 187, whence: SEEK_CUR) == 188)
        #expect(input.read(buffer: &one, size: 1) == 1)
        #expect(one == plaintext[188])
        #expect(input.seek(offset: -9, whence: SEEK_END) == plaintext.count - 9)
        var last = [UInt8](repeating: 0, count: 32)
        #expect(input.read(buffer: &last, size: 32) == 9)
        #expect(Array(last.prefix(9)) == Array(plaintext.suffix(9)))
        #expect(input.read(buffer: &one, size: 1) == -541478725)
        input.close()
        input.close()
        #expect(input.read(buffer: &one, size: 1) < 0)
    }

    @Test func rejectsNonTransportStreamAfterTransform() throws {
        let transform = try Self.transform()
        var bytes = [UInt8](repeating: 0x41, count: 600)
        try transform.apply(to: &bytes, at: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var native: UnsafeMutablePointer<AVIOContext>?
        #expect(avio_open2(&native, url.path, AVIO_FLAG_READ, nil, nil) == 0)
        let input = MediaTransformInput(native: try #require(native), playlist: nil, transform: transform)
        defer { input.close() }
        var byte: UInt8 = 0
        #expect(input.read(buffer: &byte, size: 1) < 0)
    }

    private static func transform() throws -> LiveMediaTransform {
        try LiveMediaTransform(
            scope: LiveTransformScope(offsetInPeriod: 0, lengthPerPeriod: 19, periodBytes: 188, periodCount: 0),
            keygen: LiveKeygenSpec(seed: 42, saltBias: 3, saltMultiplier: 7, shiftLeftA: 13, shiftRight: 17,
                                  shiftLeftB: 5, zeroState: 1, zeroKeyByte: 1, resetPerPeriod: true)
        )
    }
    #endif
}
