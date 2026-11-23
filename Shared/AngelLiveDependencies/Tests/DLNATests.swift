import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Observation
import AngelLiveCore
@testable import AngelLiveDependencies

@Suite("DLNA network fixtures", .serialized)
struct DLNANetworkTests {
    @Test("SSDP response and device description are discovered from fixtures")
    func discoversFixtureDevice() async throws {
        let location = try #require(URL(string: "http://192.168.1.40:8008/device.xml"))
        let ssdpHeaders = SSDPResponseParser.parse(try fixture(named: "ssdp_media_renderer", fileExtension: "txt"))
        let discoverer = StubSSDPDiscoverer(responses: [ssdpHeaders])
        let session = makeSession { request in
            #expect(request.url == location)
            return .success(statusCode: 200, data: try fixture(named: "device"))
        }
        let service = DLNAService(session: session, discoverer: discoverer)

        let devices = try await service.discoverDevices(timeout: 0.1)

        #expect(devices.count == 1)
        #expect(devices[0].udn == "uuid:fixture-tv-1")
        #expect(devices[0].friendlyName == "Fixture Living Room TV")
        #expect(devices[0].avTransportControlURL.absoluteString == "http://192.168.1.40:8008/upnp/control/avtransport")
        #expect(devices[0].expiresAt.timeIntervalSinceNow > 50)
    }

    @Test("Session discovery publishes results and failures", .timeLimit(.minutes(1)))
    @MainActor
    func discoversThroughCastingSession() async throws {
        let headers = SSDPResponseParser.parse(try fixture(named: "ssdp_media_renderer", fileExtension: "txt"))
        let service = DLNAService(
            session: makeSession { _ in
                .success(statusCode: 200, data: try fixture(named: "device"))
            },
            discoverer: StubSSDPDiscoverer(responses: [headers])
        )
        let session = DLNACastingSession(service: service, transport: StubCastingTransport(), proxy: StubCastingProxy())

        session.discover()
        #expect(session.state == .discovering)
        #expect(session.state.isBusy)
        try await waitForState(.ready, in: session)
        #expect(session.devices.map(\.udn) == ["uuid:fixture-tv-1"])

        let emptyService = DLNAService(discoverer: StubSSDPDiscoverer(responses: []))
        let emptySession = DLNACastingSession(
            service: emptyService,
            transport: StubCastingTransport(),
            proxy: StubCastingProxy()
        )
        emptySession.discover()
        try await waitForState(.failed(DLNAProtocolError.noDevices.localizedDescription), in: emptySession)
        #expect(emptySession.devices.isEmpty)
    }

    @Test("AVTransport sends SOAP actions and parses transport state")
    func sendsSOAPActions() async throws {
        let requests = RequestRecorder()
        let session = makeSession { request in
            requests.append(request)
            let action = request.value(forHTTPHeaderField: "SOAPACTION") ?? ""
            if action.contains("GetTransportInfo") {
                return .success(statusCode: 200, data: try fixture(named: "soap_transport_info"))
            }
            return .success(statusCode: 200, data: try fixture(named: "soap_success"))
        }
        let device = try makeDevice()
        let resource = DLNAMediaResource(
            url: try #require(URL(string: "https://cdn.example.com/live.m3u8?token=a&b=c")),
            title: "测试 & 直播",
            mimeType: "application/vnd.apple.mpegurl"
        )
        let client = DLNAAVTransportClient(session: session)

        try await client.setAVTransportURI(device: device, resource: resource)
        try await client.play(device: device)
        let state = try await client.transportState(device: device)
        try await client.stop(device: device)

        #expect(state == "PLAYING")
        let bodies = requests.allBodies().map { String(decoding: $0, as: UTF8.self) }
        #expect(bodies.count == 4)
        guard bodies.count == 4 else { return }
        #expect(bodies[0].contains("测试 &amp;amp; 直播"))
        #expect(bodies[0].contains("token=a&amp;amp;b=c"))
        #expect(bodies[1].contains("<u:Play"))
        #expect(bodies[2].contains("<u:GetTransportInfo"))
        #expect(bodies[3].contains("<u:Stop"))
    }

    @Test("SOAP Fault is surfaced with the device error description")
    func surfacesSOAPFault() async throws {
        let session = makeSession { _ in
            .success(statusCode: 500, data: try fixture(named: "soap_fault"))
        }
        let client = DLNAAVTransportClient(session: session)
        let device = try makeDevice()

        do {
            try await client.play(device: device)
            Issue.record("Expected Play to fail with a SOAP Fault")
        } catch let error as DLNAProtocolError {
            #expect(error == .soapFault("Transition not available"))
        }
    }

    @Test("HTTP timeout is mapped to a user-facing DLNA timeout")
    func mapsHTTPTimeout() async throws {
        let session = makeSession { _ in .failure(URLError(.timedOut)) }
        let client = DLNAAVTransportClient(session: session)
        let device = try makeDevice()

        do {
            try await client.stop(device: device)
            Issue.record("Expected Stop to time out")
        } catch let error as DLNAProtocolError {
            #expect(error == .timeout)
        }
    }

    @Test("offline HTTP connection is surfaced separately from a timeout")
    func mapsOfflineConnection() async throws {
        let session = makeSession { _ in .failure(URLError(.cannotConnectToHost)) }
        let client = DLNAAVTransportClient(session: session)
        let device = try makeDevice()

        do {
            try await client.stop(device: device)
            Issue.record("Expected Stop to report the device as offline")
        } catch let error as DLNAProtocolError {
            #expect(error == .deviceOffline)
        }
    }

    @Test("HLS proxy rewrites playlists, segments, and URI attributes")
    func rewritesHLSResourcesThroughProxy() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1280000
        low/index.m3u8
        #EXT-X-KEY:METHOD=AES-128,URI="keys/live.key"
        #EXT-X-MAP:URI="https://media.example.net/init.mp4"
        segment0001.ts?token=abc
        """
        let baseURL = try #require(URL(string: "https://cdn.example.com/live/master.m3u8"))
        let proxyBaseURL = try #require(URL(string: "http://192.168.1.20:49152"))

        let rewritten = DLNAHLSPlaylistRewriter.rewrite(
            data: Data(playlist.utf8),
            baseURL: baseURL,
            token: "session-token",
            proxyURL: { origin, token, baseURL in
                baseURL.appendingPathComponent(token).appendingPathComponent(origin.lastPathComponent)
            },
            proxyBaseURL: proxyBaseURL
        )
        let output = String(decoding: rewritten, as: UTF8.self)

        #expect(output.contains("http://192.168.1.20:49152/session-token/index.m3u8"))
        #expect(output.contains("URI=\"http://192.168.1.20:49152/session-token/live.key\""))
        #expect(output.contains("URI=\"http://192.168.1.20:49152/session-token/init.mp4\""))
        #expect(output.contains("http://192.168.1.20:49152/session-token/segment0001.ts"))
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> MockURLProtocol.Result
    ) -> URLSession {
        MockURLProtocol.install(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeDevice() throws -> DLNADevice {
        DLNADevice(
            udn: "uuid:fixture-tv-1",
            friendlyName: "Fixture TV",
            location: try #require(URL(string: "http://192.168.1.40:8008/device.xml")),
            avTransportControlURL: try #require(URL(string: "http://192.168.1.40:8008/upnp/control/avtransport")),
            expiresAt: .distantFuture
        )
    }

    private func fixture(named name: String, fileExtension: String = "xml") throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: fileExtension))
        return try Data(contentsOf: url)
    }
}

@Suite("DLNA casting session", .timeLimit(.minutes(1)))
@MainActor
struct DLNACastingSessionTests {
    @Test("Switching renderers stops the old device and releases its resource before replacing it")
    func switchesRenderersAndStops() async throws {
        let proxy = StubCastingProxy()
        let first = try device("renderer-a")
        let second = try device("renderer-b")
        let transport = StubCastingTransport(onSetURI: { device, resource in
            if device.id == second.id {
                #expect(await proxy.activeURLs == [resource.url])
            }
        })
        let session = makeSession(transport: transport, proxy: proxy)
        let firstResource = try resource("stream-a")
        let secondResource = try resource("stream-b")

        session.cast(resource: firstResource, to: first)
        #expect(session.state == .settingURI)
        try await waitForState(.playing, in: session)
        #expect(session.activeDevice == first)
        #expect(session.remoteTransportState == "PLAYING")
        let firstProxyURL = try #require(await proxy.activeURLs.first)

        session.cast(resource: secondResource, to: second)
        try await waitForState(.playing, in: session)
        #expect(session.activeDevice == second)
        let secondProxyURL = try #require(await proxy.activeURLs.first)
        #expect(await proxy.activeURLs == [secondProxyURL])
        #expect(secondProxyURL != firstProxyURL)
        #expect(await transport.commands == [
            .setURI(first.id, firstProxyURL), .play(first.id), .stop(first.id),
            .setURI(second.id, secondProxyURL), .play(second.id)
        ])

        session.stopCasting()
        #expect(session.state == .stopping)
        try await waitForState(.ready, in: session)
        #expect(session.activeDevice == nil)
        #expect(session.remoteTransportState == nil)
        #expect(await proxy.activeURLs.isEmpty)
        #expect(await transport.commands.last == .stop(second.id))
    }

    @Test("A late SetURI completion releases its candidate and cannot play", arguments: [false, true])
    func cancelsInFlightSetURI(replace: Bool) async throws {
        let (started, signalStart) = AsyncStream<URL>.makeStream()
        let (hold, allowCompletion) = AsyncStream<Void>.makeStream()
        defer { allowCompletion.finish() }
        let first = try device("renderer-a")
        let second = try device("renderer-b")
        let transport = StubCastingTransport(onSetURI: { device, resource in
            guard device.id == first.id else { return }
            signalStart.yield(resource.url)
            // Simulate a response arriving even after the caller cancels.
            await Task.detached { for await _ in hold {} }.value
        })
        let proxy = StubCastingProxy()
        let session = makeSession(transport: transport, proxy: proxy)
        let firstResource = try resource("stream-a")
        let secondResource = try resource("stream-b")

        session.cast(resource: firstResource, to: first)
        var start = started.makeAsyncIterator()
        let firstProxyURL = try #require(await start.next())
        #expect(await proxy.activeURLs == [firstProxyURL])
        if replace {
            session.cast(resource: secondResource, to: second)
            #expect(session.state == .settingURI)
        } else {
            session.stopCasting()
            #expect(session.state == .ready)
        }

        allowCompletion.finish()
        var releases = proxy.releases.makeAsyncIterator()
        #expect(await releases.next() == firstProxyURL)
        #expect(await !transport.commands.contains(.play(first.id)))
        if replace {
            try await waitForState(.playing, in: session)
            #expect(session.activeDevice == second)
            #expect(await proxy.activeURLs.count == 1)
            session.stopCasting()
            try await waitForState(.ready, in: session)
        } else {
            #expect(session.state == .ready)
            #expect(session.activeDevice == nil)
        }
        #expect(await proxy.activeURLs.isEmpty)
    }

    @Test("A Play error releases the prepared media and leaves no active renderer")
    func handlesPlayFailure() async throws {
        let failure = DLNAProtocolError.soapFault("Fixture Play fault")
        let transport = StubCastingTransport(playError: failure)
        let proxy = StubCastingProxy()
        let session = makeSession(transport: transport, proxy: proxy)

        session.cast(resource: try resource("stream"), to: try device("renderer"))
        try await waitForState(.failed(failure.localizedDescription), in: session)

        #expect(session.activeDevice == nil)
        #expect(session.remoteTransportState == nil)
        #expect(await proxy.activeURLs.isEmpty)
    }

    @Test("A Stop error clears the active renderer and releases its media")
    func handlesStopFailure() async throws {
        let failure = DLNAProtocolError.deviceOffline
        let transport = StubCastingTransport(stopError: failure)
        let proxy = StubCastingProxy()
        let session = makeSession(transport: transport, proxy: proxy)

        session.cast(resource: try resource("stream"), to: try device("renderer"))
        try await waitForState(.playing, in: session)
        session.stopCasting()
        try await waitForState(.failed(failure.localizedDescription), in: session)

        #expect(session.activeDevice == nil)
        #expect(session.remoteTransportState == nil)
        #expect(await proxy.activeURLs.isEmpty)
    }

    @Test("A terminal renderer state clears the session", arguments: [" stopped\n", "NO_MEDIA_PRESENT"])
    func handlesRemoteStop(remoteState: String) async throws {
        let transport = StubCastingTransport(remoteState: remoteState)
        let proxy = StubCastingProxy()
        let session = makeSession(transport: transport, proxy: proxy, pollInterval: 0.5)

        session.cast(resource: try resource("stream"), to: try device("renderer"))
        try await waitForState(.playing, in: session)
        try await waitForState(.ready, in: session)

        #expect(session.activeDevice == nil)
        #expect(session.remoteTransportState == nil)
        #expect(await proxy.activeURLs.isEmpty)
    }

    @Test("A polling error releases the active media and clears the renderer")
    func handlesPollingError() async throws {
        let failure = DLNAProtocolError.deviceOffline
        let transport = StubCastingTransport(pollError: failure)
        let proxy = StubCastingProxy()
        let session = makeSession(transport: transport, proxy: proxy, pollInterval: 0.5)
        session.cast(resource: try resource("stream"), to: try device("renderer"))
        try await waitForState(.playing, in: session)
        try await waitForState(.failed(failure.localizedDescription), in: session)
        #expect(session.activeDevice == nil)
        #expect(session.remoteTransportState == nil)
        #expect(await proxy.activeURLs.isEmpty)
    }

    @Test("Discovery without devices reports failure")
    func handlesDiscoveryFailure() async throws {
        let session = makeSession(transport: StubCastingTransport(), proxy: StubCastingProxy())
        session.discover()
        try await waitForState(.failed(DLNAProtocolError.noDevices.localizedDescription), in: session)
        #expect(session.devices.isEmpty)
        #expect(session.activeDevice == nil)
    }

    @Test("Discovery publishes discovered devices and becomes ready")
    func handlesDiscoverySuccess() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CastingDiscoveryURLProtocol.self]
        let service = DLNAService(
            session: URLSession(configuration: configuration),
            discoverer: StubSSDPDiscoverer(responses: [["location": "http://renderer.example.invalid/device.xml"]])
        )
        let session = DLNACastingSession(service: service, transport: StubCastingTransport(), proxy: StubCastingProxy())
        session.discover()
        try await waitForState(.ready, in: session)
        #expect(session.devices.count == 1)
        #expect(session.activeDevice == nil)
    }

    @Test("Cancelling discovery restores playback without stopping it")
    func cancelsScanDuringPlayback() async throws {
        let transport = StubCastingTransport()
        let proxy = StubCastingProxy()
        let session = makeSession(transport: transport, proxy: proxy)
        let renderer = try device("renderer")

        session.discover()
        session.cancelDiscovery()
        #expect(session.state == .idle)

        session.cast(resource: try resource("stream"), to: renderer)
        try await waitForState(.playing, in: session)
        session.discover()
        #expect(session.state == .discovering)
        session.cancelDiscovery()

        #expect(session.state == .playing)
        #expect(session.activeDevice == renderer)
        #expect(session.remoteTransportState == "PLAYING")
        #expect(await proxy.activeURLs.count == 1)
        #expect(await !transport.commands.contains(.stop(renderer.id)))
        session.stopCasting()
        try await waitForState(.ready, in: session)
    }

    private func makeSession(
        transport: StubCastingTransport,
        proxy: StubCastingProxy,
        pollInterval: TimeInterval = 5.0
    ) -> DLNACastingSession {
        DLNACastingSession(
            service: DLNAService(discoverer: StubSSDPDiscoverer(responses: [])),
            transport: transport,
            proxy: proxy,
            pollInterval: pollInterval
        )
    }

    private func device(_ name: String) throws -> DLNADevice {
        let location = try #require(URL(string: "http://\(name).example.invalid"))
        return DLNADevice(
            udn: "uuid:\(name)",
            friendlyName: name,
            location: location.appendingPathComponent("device.xml"),
            avTransportControlURL: location.appendingPathComponent("transport"),
            expiresAt: .distantFuture
        )
    }

    private func resource(_ name: String) throws -> DLNAMediaResource {
        DLNAMediaResource(
            url: try #require(URL(string: "https://media.example.invalid/\(name).m3u8")),
            title: name,
            mimeType: "application/vnd.apple.mpegurl",
            requestHeaders: ["User-Agent": "Fixture player"]
        )
    }
}

private final class CastingDiscoveryURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let fixture = try #require(Bundle.module.url(forResource: "device", withExtension: "xml"))
            let data = try Data(contentsOf: fixture)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

@MainActor
private func waitForState(_ expected: DLNACastingSessionState, in session: DLNACastingSession) async throws {
    while true {
        let (updates, continuation) = AsyncStream<Void>.makeStream()
        let state = withObservationTracking { session.state } onChange: { continuation.finish() }
        if state == expected { return }
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()
        try Task.checkCancellation()
    }
}

private actor StubCastingTransport: DLNAAVTransportControlling {
    enum Command: Equatable {
        case setURI(String, URL)
        case play(String)
        case stop(String)
    }

    private(set) var commands: [Command] = []
    private let remoteState: String
    private let playError: DLNAProtocolError?
    private let stopError: DLNAProtocolError?
    private let pollError: DLNAProtocolError?
    private let onSetURI: @Sendable (DLNADevice, DLNAMediaResource) async -> Void

    init(
        remoteState: String = "PLAYING",
        playError: DLNAProtocolError? = nil,
        stopError: DLNAProtocolError? = nil,
        pollError: DLNAProtocolError? = nil,
        onSetURI: @escaping @Sendable (DLNADevice, DLNAMediaResource) async -> Void = { _, _ in }
    ) {
        self.remoteState = remoteState
        self.playError = playError
        self.stopError = stopError
        self.pollError = pollError
        self.onSetURI = onSetURI
    }

    func setAVTransportURI(device: DLNADevice, resource: DLNAMediaResource) async throws {
        commands.append(.setURI(device.id, resource.url))
        await onSetURI(device, resource)
    }

    func play(device: DLNADevice) async throws {
        commands.append(.play(device.id))
        if let playError { throw playError }
    }

    func stop(device: DLNADevice) async throws {
        commands.append(.stop(device.id))
        if let stopError { throw stopError }
    }

    func transportState(device: DLNADevice) async throws -> String {
        if let pollError { throw pollError }
        return remoteState
    }
}

private actor StubCastingProxy: DLNAMediaProxying {
    private(set) var activeURLs: Set<URL> = []
    let releases: AsyncStream<URL>
    private let releaseEvents: AsyncStream<URL>.Continuation

    init() {
        (releases, releaseEvents) = AsyncStream.makeStream()
    }

    func prepare(resource: DLNAMediaResource) async throws -> DLNAMediaResource {
        let url = try #require(URL(string: "http://proxy.example.invalid/\(UUID().uuidString)"))
        activeURLs.insert(url)
        return DLNAMediaResource(
            url: url,
            title: resource.title,
            mimeType: resource.mimeType,
            isLive: resource.isLive
        )
    }

    func release(resource: DLNAMediaResource) {
        activeURLs.remove(resource.url)
        releaseEvents.yield(resource.url)
    }
}

private final class StubSSDPDiscoverer: SSDPDiscovering, @unchecked Sendable {
    let responses: [[String: String]]

    init(responses: [[String: String]]) {
        self.responses = responses
    }

    func discover(timeout: TimeInterval) async throws -> [[String: String]] {
        responses
    }

    func cancel() {}
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data] = []

    func append(_ request: URLRequest) {
        lock.lock()
        if let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream) {
            bodies.append(body)
        }
        lock.unlock()
    }

    func allBodies() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }
}

private final class MockURLProtocol: URLProtocol {
    struct Result {
        let statusCode: Int
        let data: Data
        let error: Error?

        static func success(statusCode: Int, data: Data) -> Result {
            Result(statusCode: statusCode, data: data, error: nil)
        }

        static func failure(_ error: Error) -> Result {
            Result(statusCode: 0, data: Data(), error: error)
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) throws -> Result)?

    static func install(handler: @escaping (URLRequest) throws -> Result) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result: Result
        do {
            Self.lock.lock()
            let currentHandler = Self.handler
            Self.lock.unlock()
            guard let currentHandler else { throw URLError(.badServerResponse) }
            result = try currentHandler(request)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        if let error = result.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: result.statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/xml"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
