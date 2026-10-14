#if canImport(KSPlayer)
import Foundation
import Testing
import AngelLiveCore
import KSPlayer
import NIO
import NIOHTTP1
@testable import AngelLiveDependencies

@Suite("Media transform real HLS demux", .serialized)
struct MediaTransformIntegrationTests {
    static func transform(seed: UInt32 = 0x12345678) throws -> LiveMediaTransform {
        try LiveMediaTransform(
            scope: LiveTransformScope(offsetInPeriod: 0, lengthPerPeriod: 16, periodBytes: 188, periodCount: 0),
            keygen: LiveKeygenSpec(seed: seed, saltBias: 1, saltMultiplier: 0x9E3779B9,
                shiftLeftA: 13, shiftRight: 17, shiftLeftB: 5,
                zeroState: 0x6D2B79F5, zeroKeyByte: 0xA5, resetPerPeriod: true)
        )
    }

    static func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: nil))
    }

    static func options() -> KSOptions {
        let options = KSOptions()
        options.formatContextOptions["rw_timeout"] = 2_000_000
        return options
    }

    static func packets(_ context: FormatContext) -> [Data] {
        // FormatContext starts tracks disabled; KSMEPlayer enables selected tracks
        // before reading. Match that public consumption contract in this IO test.
        for track in context.assetTracks where track.mediaType == .video || track.mediaType == .audio {
            track.isEnabled = true
        }
        var result: [Data] = []
        while let packet = context.read(), let raw = packet.corePacket {
            if let bytes = raw.pointee.data, raw.pointee.size > 0 {
                result.append(Data(bytes: bytes, count: Int(raw.pointee.size)))
            }
            if result.count > 100 { break } // This fixture has exactly 24 video frames.
        }
        return result
    }

    @Test("Restored master playlist produces every original compressed video packet")
    func restoresAllSegmentsBeforeProbe() throws {
        let plain = try FormatContext(url: Self.fixture("media-transform-plain.m3u8"), options: Self.options())
        defer { plain.close() }
        let expected = Self.packets(plain)
        #expect(expected.count == 24)
        let restored = try MediaTransformContextFactory.make(
            url: Self.fixture("media-transform-master.m3u8"), options: Self.options(),
            transform: Self.transform(), interrupt: IOInterruptContext()
        )
        defer { restored.close() }
        #expect(Self.packets(restored) == expected)
        #expect(restored.performSeek(time: 0, flags: 0) >= 0)
        #expect(plain.performSeek(time: 0, flags: 0) >= 0)
        #expect(Self.packets(restored) == Self.packets(plain))
        // A nonzero time preserves KSPlayer's default backward keyframe policy;
        // its public implementation overrides flags to zero for exactly time 0.
        #expect(restored.performSeek(time: 0.01, flags: 1) >= 0)
        #expect(Self.packets(restored) == expected)
    }

    @Test("Interrupted opening is rejected before transferring context ownership")
    func cancellationDuringOpening() throws {
        #expect(throws: (any Error).self) {
            try MediaTransformContextFactory.make(
                url: Self.fixture("media-transform-master.m3u8"), options: Self.options(),
                transform: Self.transform(), interrupt: IOInterruptContext { true }
            )
        }
    }

    @Test("Incorrect transform cannot be accepted as a valid TS stream")
    func rejectsWrongSeed() throws {
        #expect(throws: (any Error).self) {
            let context = try MediaTransformContextFactory.make(
                url: Self.fixture("media-transform-master.m3u8"), options: Self.options(),
                transform: Self.transform(seed: 0x87654321), interrupt: IOInterruptContext()
            )
            context.close()
        }
    }

    @Test("HTTP redirects, request headers and extensionless segment roles survive wrapping")
    func restoresHTTPStream() async throws {
        var resources: [String: Data] = [:]
        for name in ["media-transform-master.m3u8", "media-transform-scrambled.m3u8"] {
            resources[name] = try Data(contentsOf: Self.fixture(name))
        }
        for index in 0..<4 {
            let name = "media-transform-scrambled-\(index).bin"
            resources[name] = try Data(contentsOf: Self.fixture(name))
        }
        let immutableResources = resources
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(MediaTransformFixtureHTTPHandler(resources: immutableResources))
                }
            }.bind(host: "127.0.0.1", port: 0).get()
        do {
            let port = try #require(server.localAddress?.port)
            let options = Self.options()
            options.appendHeader(["X-Fixture": "media-transform-test"])
            let context = try MediaTransformContextFactory.make(
                url: #require(URL(string: "http://127.0.0.1:\(port)/redirect")), options: options,
                transform: Self.transform(), interrupt: IOInterruptContext()
            )
            defer { context.close() }
            let actual = Self.packets(context)
            let plain = try FormatContext(url: Self.fixture("media-transform-plain.m3u8"), options: Self.options())
            defer { plain.close() }
            #expect(actual.count == 24)
            #expect(actual == Self.packets(plain))
            try await server.close().get()
            try await group.shutdownGracefully()
        } catch {
            try? await server.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
    }
}

/// Test-only loopback server. State belongs to its NIO channel's event loop.
private final class MediaTransformFixtureHTTPHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private let resources: [String: Data]
    init(resources: [String: Data]) { self.resources = resources }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case let .head(request) = unwrapInboundIn(data) else { return }
        var headers = NIOHTTP1.HTTPHeaders()
        let status: HTTPResponseStatus
        var body = Data()
        if request.headers.first(name: "X-Fixture") != "media-transform-test" {
            status = .forbidden
        } else if request.uri == "/redirect" {
            status = .found
            headers.add(name: "Location", value: "/media/media-transform-master.m3u8")
        } else {
            let name = String(request.uri.split(separator: "/").last ?? "")
            if let resource = resources[name], request.uri.hasPrefix("/media/") {
                body = resource
                status = .ok
            } else {
                status = .notFound
            }
        }
        headers.add(name: "Content-Length", value: String(body.count))
        headers.add(name: "Content-Type", value: request.uri.hasSuffix(".m3u8") ? "application/vnd.apple.mpegurl" : "application/octet-stream")
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: request.version, status: status, headers: headers))), promise: nil)
        if !body.isEmpty {
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
#endif
