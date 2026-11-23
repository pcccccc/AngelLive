import Foundation
import Observation
import AngelLiveCore

public enum DLNACastingSessionState: Equatable, Sendable {
    case idle
    case discovering
    case ready
    case settingURI
    case playing
    case stopping
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .discovering, .settingURI, .stopping:
            return true
        case .idle, .ready, .playing, .failed:
            return false
        }
    }
}

public protocol DLNAAVTransportControlling: Sendable {
    func setAVTransportURI(device: DLNADevice, resource: DLNAMediaResource) async throws
    func play(device: DLNADevice) async throws
    func stop(device: DLNADevice) async throws
    func transportState(device: DLNADevice) async throws -> String
}

extension DLNAAVTransportClient: DLNAAVTransportControlling {}

protocol DLNAMediaProxying: Sendable {
    func prepare(resource: DLNAMediaResource) async throws -> DLNAMediaResource
    func release(resource: DLNAMediaResource) async
}

extension DLNALocalMediaProxy: DLNAMediaProxying {}

@Observable
@MainActor
public final class DLNACastingSession {
    public private(set) var devices: [DLNADevice] = []
    public private(set) var state: DLNACastingSessionState = .idle
    public private(set) var activeDevice: DLNADevice?
    public private(set) var remoteTransportState: String?

    private let service: DLNAService
    private let transport: any DLNAAVTransportControlling
    private let mediaProxy: any DLNAMediaProxying
    private let pollInterval: Duration

    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryID = UUID()
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var activeResource: DLNAMediaResource?

    public convenience init(
        service: DLNAService = DLNAService(),
        transport: any DLNAAVTransportControlling = DLNAAVTransportClient(),
        mediaProxy: DLNALocalMediaProxy = .shared,
        pollInterval: TimeInterval = 5.0
    ) {
        self.init(service: service, transport: transport, proxy: mediaProxy, pollInterval: pollInterval)
    }

    init(
        service: DLNAService,
        transport: any DLNAAVTransportControlling,
        proxy: any DLNAMediaProxying,
        pollInterval: TimeInterval = 5.0
    ) {
        self.service = service
        self.transport = transport
        self.mediaProxy = proxy
        self.pollInterval = .seconds(max(0.5, pollInterval))
    }

    deinit {
        discoveryTask?.cancel()
        commandTask?.cancel()
        pollingTask?.cancel()
        if let activeResource {
            Task { [mediaProxy] in await mediaProxy.release(resource: activeResource) }
        }
    }

    public func discover() {
        let previousScan = discoveryTask
        previousScan?.cancel()
        let discoveryID = UUID()
        self.discoveryID = discoveryID
        devices.removeAll(keepingCapacity: true)
        // Cast and Stop own the visible state while their commands are in flight.
        if state != .settingURI && state != .stopping {
            state = .discovering
        }
        discoveryTask = Task { [weak self, service] in
            // The service has one SSDP socket. Let the previous scan finish cancelling
            // before starting another on that same service.
            await previousScan?.value
            guard !Task.isCancelled else { return }
            do {
                let devices = try await service.discoverDevices()
                guard !Task.isCancelled, let self, self.discoveryID == discoveryID else { return }
                self.devices = devices
                if self.state == .discovering {
                    self.state = self.activeDevice == nil ? .ready : .playing
                }
            } catch {
                guard !Task.isCancelled, let self, self.discoveryID == discoveryID,
                      self.state == .discovering else { return }
                if error is CancellationError || (error as? DLNAProtocolError) == .requestCancelled {
                    self.state = self.activeDevice == nil ? .idle : .playing
                } else {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    public func cancelDiscovery() {
        discoveryID = UUID()
        discoveryTask?.cancel()
        if state == .discovering {
            state = activeDevice == nil ? .idle : .playing
        }
    }

    public func cast(resource: DLNAMediaResource, to device: DLNADevice) {
        let previousCommand = commandTask
        let sessionID = beginCommand(state: .settingURI)
        commandTask = Task { [weak self] in
            // Finish any cancelled command's cleanup before preparing another
            // resource or sending a new command to the renderer.
            await previousCommand?.value
            guard let self, !Task.isCancelled else { return }
            var candidateResource: DLNAMediaResource?
            do {
                if let oldDevice = activeDevice, oldDevice.id != device.id {
                    try? await transport.stop(device: oldDevice)
                    try checkSession(sessionID)
                }
                if let oldResource = takeActiveResource() {
                    await mediaProxy.release(resource: oldResource)
                    try checkSession(sessionID)
                }

                let preparedResource = try await mediaProxy.prepare(resource: resource)
                candidateResource = preparedResource
                try checkSession(sessionID)
                try await transport.setAVTransportURI(device: device, resource: preparedResource)
                try checkSession(sessionID)
                try await transport.play(device: device)
                try checkSession(sessionID)

                activeResource = preparedResource
                activeDevice = device
                remoteTransportState = "PLAYING"
                state = .playing
                startTransportPolling(for: device, sessionID: sessionID)
            } catch {
                if let candidateResource {
                    await mediaProxy.release(resource: candidateResource)
                }
                guard self.sessionID == sessionID else { return }
                state = error is CancellationError ? .ready : .failed(error.localizedDescription)
            }
        }
    }

    public func stopCasting() {
        let device = activeDevice
        let previousCommand = commandTask
        let sessionID = beginCommand(state: device == nil ? .ready : .stopping)
        guard let device else { return }
        commandTask = Task { [self] in
            await previousCommand?.value
            guard !Task.isCancelled else { return }
            let finalState: DLNACastingSessionState
            do {
                try await transport.stop(device: device)
                finalState = .ready
            } catch {
                finalState = .failed(error.localizedDescription)
            }
            await finishSession(sessionID, state: finalState)
        }
    }

    private func beginCommand(state: DLNACastingSessionState) -> UUID {
        commandTask?.cancel()
        pollingTask?.cancel()
        pollingTask = nil
        sessionID = UUID()
        remoteTransportState = nil
        self.state = state
        return sessionID
    }

    private func checkSession(_ id: UUID) throws {
        guard sessionID == id else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func takeActiveResource() -> DLNAMediaResource? {
        let resource = activeResource
        activeResource = nil
        activeDevice = nil
        remoteTransportState = nil
        return resource
    }

    private func finishSession(_ id: UUID, state: DLNACastingSessionState) async {
        guard sessionID == id else { return }
        if let resource = takeActiveResource() {
            await mediaProxy.release(resource: resource)
        }
        guard sessionID == id else { return }
        self.state = state
    }

    private func startTransportPolling(for device: DLNADevice, sessionID: UUID) {
        pollingTask = Task { [weak self, transport, pollInterval] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: pollInterval)
                    let value = try await transport.transportState(device: device)
                    guard !Task.isCancelled, let self, self.sessionID == sessionID else { return }
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if normalized == "STOPPED" || normalized == "NO_MEDIA_PRESENT" {
                        await self.finishSession(sessionID, state: .ready)
                        return
                    }
                    if !normalized.isEmpty {
                        self.remoteTransportState = normalized
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, let self, self.sessionID == sessionID else { return }
                    await self.finishSession(sessionID, state: .failed(error.localizedDescription))
                    return
                }
            }
        }
    }
}
