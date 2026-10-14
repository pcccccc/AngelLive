import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Declarative segment byte restoration")
struct LiveMediaTransformTests {
    private func transform(reset: Bool = true, count: Int = 3) throws -> LiveMediaTransform {
        try LiveMediaTransform(
            scope: LiveTransformScope(offsetInPeriod: 2, lengthPerPeriod: 4, periodBytes: 8, periodCount: count),
            keygen: LiveKeygenSpec(
                seed: 1, saltBias: 2, saltMultiplier: 3,
                shiftLeftA: 13, shiftRight: 17, shiftLeftB: 5,
                zeroState: 11, zeroKeyByte: 7, resetPerPeriod: reset
            )
        )
    }

    // Independently calculated with explicit UInt32 masking after each left shift.
    @Test(arguments: [true, false])
    func goldenVectors(reset: Bool) throws {
        var bytes = Array(UInt8(0)...UInt8(27))
        try transform(reset: reset).apply(to: &bytes, at: 0)
        let expected: [UInt8] = reset
            ? [0, 1, 229, 4, 71, 64, 6, 7, 8, 9, 2, 3, 37, 119, 14, 15, 16, 17, 191, 30, 252, 44, 22, 23, 24, 25, 26, 27]
            : [0, 1, 229, 4, 71, 64, 6, 7, 8, 9, 245, 159, 182, 90, 14, 15, 16, 17, 189, 25, 233, 241, 22, 23, 24, 25, 26, 27]
        #expect(bytes == expected)
    }

    @Test(arguments: [true, false], [0, 3])
    func chunkingSeekingAndInvolution(reset: Bool, count: Int) throws {
        let config = try transform(reset: reset, count: count)
        let input = (0..<513).map { UInt8(truncatingIfNeeded: $0) }
        var whole = input
        try config.apply(to: &whole, at: 0)
        var chunks: [UInt8] = []
        for offset in stride(from: 0, to: input.count, by: 7) {
            var chunk = Array(input[offset..<min(offset + 7, input.count)])
            try config.apply(to: &chunk, at: Int64(offset))
            chunks += chunk
        }
        #expect(chunks == whole)
        for offset in [1, 2, 3, 5, 6, 7, 8, 10, 21, 24, 509] {
            var sought = Array(input[offset..<min(offset + 4, input.count)])
            try config.apply(to: &sought, at: Int64(offset))
            #expect(sought == Array(whole[offset..<min(offset + 4, input.count)]))
        }
        try config.apply(to: &whole, at: 0)
        #expect(whole == input)
    }

    @Test("Continuous state skips plaintext, including a short final period")
    func continuousStateIgnoresPlaintext() throws {
        let config = try transform(reset: false, count: 0)
        var bytes = [UInt8](repeating: 0, count: 20)
        try config.apply(to: &bytes, at: 0)
        #expect(bytes == [0, 0, 231, 7, 67, 69, 0, 0, 0, 0, 255, 148, 186, 87, 0, 0, 0, 0, 175, 10])
    }

    @Test("Huge random offsets use jump ahead and preserve read boundaries")
    func hugeOffset() throws {
        let config = try transform(reset: false, count: 0)
        let offset = Int64.max - 103
        var full = [UInt8](repeating: 0, count: 100)
        try config.apply(to: &full, at: offset)
        var partial = [UInt8](repeating: 0, count: 17)
        try config.apply(to: &partial, at: offset + 41)
        #expect(partial == Array(full[41..<58]))
    }

    @Test("Zero replacements are applied only at initialization and output")
    func zeroFallbacks() throws {
        let scope = try LiveTransformScope(offsetInPeriod: 0, lengthPerPeriod: 4, periodBytes: 4, periodCount: 0)
        let keygen = try LiveKeygenSpec(seed: 0, saltBias: 0, saltMultiplier: 0,
            shiftLeftA: 13, shiftRight: 17, shiftLeftB: 5,
            zeroState: 1, zeroKeyByte: 0, resetPerPeriod: true)
        var bytes = [UInt8](repeating: 0, count: 8)
        try LiveMediaTransform(scope: scope, keygen: keygen).apply(to: &bytes, at: 0)
        #expect(bytes == [33, 1, 197, 79, 33, 1, 197, 79])
        let zeroKeygen = try LiveKeygenSpec(seed: 0, saltBias: 0, saltMultiplier: 0,
            shiftLeftA: 13, shiftRight: 17, shiftLeftB: 5,
            zeroState: 0, zeroKeyByte: 7, resetPerPeriod: false)
        bytes = [0, 1, 2, 3]
        try LiveMediaTransform(scope: scope, keygen: zeroKeygen).apply(to: &bytes, at: 0)
        #expect(bytes == [7, 6, 5, 4])
    }

    @Test("UInt32 salt and period index wrap exactly")
    func saltWraparound() throws {
        let config = try LiveMediaTransform(
            scope: LiveTransformScope(offsetInPeriod: 2, lengthPerPeriod: 4, periodBytes: 8, periodCount: 0),
            keygen: LiveKeygenSpec(seed: 1, saltBias: .max, saltMultiplier: .max,
                shiftLeftA: 13, shiftRight: 17, shiftLeftB: 5,
                zeroState: 11, zeroKeyByte: 7, resetPerPeriod: true)
        )
        for (period, expected) in [(Int64(0), [UInt8](arrayLiteral: 107, 11, 110, 51)),
                                    (1, [33, 1, 197, 79]),
                                    (4_294_967_295, [99, 3, 71, 73]),
                                    (4_294_967_296, [107, 11, 110, 51])] {
            var bytes = [UInt8](repeating: 0, count: 4)
            try config.apply(to: &bytes, at: period * 8 + 2)
            #expect(bytes == expected)
        }
    }

    @Test("Invalid construction and offsets fail without modifying bytes")
    func invalidParameters() throws {
        for tuple in [(-1, 1, 8, 0), (0, 0, 8, 0), (0, 1, 0, 0), (7, 2, 8, 0), (0, 1, 8, -1), (Int.max, 1, Int.max, 0), (0, 1, Int.max, 2)] {
            #expect(throws: LiveMediaTransformError.invalidScope) {
                try LiveTransformScope(offsetInPeriod: tuple.0, lengthPerPeriod: tuple.1, periodBytes: tuple.2, periodCount: tuple.3)
            }
        }
        #expect(throws: LiveMediaTransformError.invalidKeygen) {
            try LiveKeygenSpec(seed: 0, saltBias: 0, saltMultiplier: 0,
                shiftLeftA: 0, shiftRight: 17, shiftLeftB: 5,
                zeroState: 0, zeroKeyByte: 0, resetPerPeriod: false)
        }
        let config = try transform()
        #expect(throws: LiveMediaTransformError.invalidTargets) {
            try LiveMediaTransform(scope: config.scope, keygen: config.keygen, targets: [])
        }
        #expect(throws: LiveMediaTransformError.invalidTargets) {
            try LiveMediaTransform(scope: config.scope, keygen: config.keygen, targets: [.segment, .segment])
        }
        var bytes: [UInt8] = [1, 2]
        #expect(throws: LiveMediaTransformError.invalidOffset) { try config.apply(to: &bytes, at: -1) }
        #expect(throws: LiveMediaTransformError.invalidOffset) { try config.apply(to: &bytes, at: Int64.max) }
        #expect(bytes == [1, 2])
    }

    @Test("Wire transform defaults targets but rejects invalid required configuration")
    func strictDecode() throws {
        let config = try transform()
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(LiveMediaTransform.self, from: data) == config)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "targets")
        #expect(try JSONDecoder().decode(LiveMediaTransform.self, from: JSONSerialization.data(withJSONObject: object)).targets == [.segment])
        var keygen = try #require(object["keygen"] as? [String: Any])
        keygen["algorithm"] = "unsupported"
        object["keygen"] = keygen
        let invalid = try JSONSerialization.data(withJSONObject: ["mediaTransform": object])
        #expect(throws: LiveMediaTransformError.invalidKeygen) {
            try JSONDecoder().decode(LivePlaybackHints.self, from: invalid)
        }
        for text in [#"{"mediaTransform":"invalid"}"#, #"{"mediaTransform":{}}"#] {
            #expect(throws: LiveMediaTransformError.self) {
                try JSONDecoder().decode(LivePlaybackHints.self, from: Data(text.utf8))
            }
        }
        #expect(try JSONDecoder().decode(LivePlaybackHints.self, from: Data(#"{"mediaTransform":null}"#.utf8)).mediaTransform == nil)
    }

    @Test("Malformed numeric fields and unsupported targets reject the whole quality response")
    func strictQualityDecode() throws {
        let config = try transform()
        let quality = LiveQualityDetail(roomId: "room", title: "source", qn: 0,
            url: "https://media.example.invalid/master.m3u8", liveCodeType: .hls, liveType: .placeholder,
            playbackHints: LivePlaybackHints(mediaTransform: config))
        let encoded = try JSONEncoder().encode(quality)
        let pristine = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (key, value) in [("seed", -1 as Any), ("seed", 4_294_967_296 as Any),
                             ("shiftLeftA", 32 as Any), ("shiftRight", 0 as Any),
                             ("resetPerPeriod", "false" as Any)] {
            var object = pristine
            var hints = try #require(object["playbackHints"] as? [String: Any])
            var transform = try #require(hints["mediaTransform"] as? [String: Any])
            var keygen = try #require(transform["keygen"] as? [String: Any])
            keygen[key] = value
            transform["keygen"] = keygen
            hints["mediaTransform"] = transform
            object["playbackHints"] = hints
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: LiveMediaTransformError.self) {
                try JSONDecoder().decode(LiveQualityDetail.self, from: data)
            }
        }
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        let invalidTargets: [Any] = [["initSegment"], ["segment", "segment"], [String](), NSNull()]
        for targets in invalidTargets {
            object["targets"] = targets
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: LiveMediaTransformError.self) {
                try JSONDecoder().decode(LiveMediaTransform.self, from: data)
            }
        }
    }

    @Test("Media restoration overrides AV preference and low latency")
    func routingForcesME() throws {
        let quality = LiveQualityDetail(roomId: "room", title: "source", qn: 0,
            url: "https://media.example.invalid/master.m3u8", liveCodeType: .hls, liveType: .placeholder,
            playbackHints: LivePlaybackHints(streamFormat: .hlsVod, latencyMode: .lowLatency,
                preferredEngines: [.avPlayer], mediaTransform: try transform()))
        let plan = RoomPlaybackResolver.resolvePlan(selectedQuality: quality)
        #expect(plan.playerKinds == [.mePlayer])
        #expect(plan.isHLS)
        #expect(!plan.isLive)
    }

    @Test("Console redacts object and diagnostic JSON string key material")
    func consoleRedaction() throws {
        let payload: [String: Any] = ["playbackHints": ["mediaTransform": ["keygen": ["seed": 123, "saltBias": 456]]]]
        let result = LiveParsePluginManager.redactedLoginTransactionConsoleValue(payload)
        let text = try #require(String(data: JSONSerialization.data(withJSONObject: result), encoding: .utf8))
        #expect(text.contains("<redacted>"))
        #expect(!text.contains("123"))
        #expect(!text.contains("456"))
        let wire = try #require(String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8))
        let safe = LiveParsePluginManager.redactedMediaTransformConsoleText(wire)
        #expect(!safe.contains("123"))
        #expect(!safe.contains("456"))
        #expect(LiveParsePluginManager.redactedMediaTransformConsoleText("mediaTransform malformed") == "<redacted media transform payload>")
    }
}
