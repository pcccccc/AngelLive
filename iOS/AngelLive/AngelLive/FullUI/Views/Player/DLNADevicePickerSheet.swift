import SwiftUI
import Observation
import AngelLiveCore
import AngelLiveDependencies

enum DLNACastSessionState: Equatable {
    case idle
    case discovering
    case ready
    case settingURI
    case playing
    case stopping
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .discovering, .settingURI, .stopping:
            return true
        case .idle, .ready, .playing, .failed:
            return false
        }
    }
}

@Observable
@MainActor
final class DLNACastCoordinator {
    var devices: [DLNADevice] = []
    var state: DLNACastSessionState = .idle
    var activeDevice: DLNADevice?
    /// Last state reported by AVTransport (for example PLAYING or PAUSED_PLAYBACK).
    var remoteTransportState: String?

    private let service: DLNAService
    private let transport: DLNAAVTransportClient
    private let mediaProxy: DLNALocalMediaProxy
    private let pollInterval: TimeInterval
    private var discoveryTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var discoveryID = UUID()
    private var sessionID = UUID()
    private var activeResource: DLNAMediaResource?

    init(
        service: DLNAService = DLNAService(),
        transport: DLNAAVTransportClient = DLNAAVTransportClient(),
        mediaProxy: DLNALocalMediaProxy = .shared,
        pollInterval: TimeInterval = 5.0
    ) {
        self.service = service
        self.transport = transport
        self.mediaProxy = mediaProxy
        self.pollInterval = max(0.5, pollInterval)
    }

    func discover() {
        discoveryTask?.cancel()
        let discoveryID = UUID()
        self.discoveryID = discoveryID
        devices.removeAll(keepingCapacity: true)
        state = .discovering
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let devices = try await service.discoverDevices()
                try Task.checkCancellation()
                guard self.discoveryID == discoveryID else { return }
                self.devices = devices
                self.state = self.activeDevice == nil ? .ready : .playing
            } catch is CancellationError {
                // The sheet was dismissed or a new scan was requested.
            } catch {
                guard self.discoveryID == discoveryID else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func cast(resource: DLNAMediaResource, to device: DLNADevice) {
        commandTask?.cancel()
        pollingTask?.cancel()
        pollingTask = nil
        remoteTransportState = nil
        let sessionID = UUID()
        self.sessionID = sessionID
        state = .settingURI
        commandTask = Task { [weak self] in
            guard let self else { return }
            var candidateResource: DLNAMediaResource?
            do {
                if let oldDevice = activeDevice, oldDevice.id != device.id {
                    try? await transport.stop(device: oldDevice)
                }
                if let activeResource {
                    await mediaProxy.release(resource: activeResource)
                    self.activeResource = nil
                }
                guard self.sessionID == sessionID else { return }
                activeDevice = nil
                let preparedResource = try await mediaProxy.prepare(resource: resource)
                candidateResource = preparedResource
                try await transport.setAVTransportURI(device: device, resource: preparedResource)
                try Task.checkCancellation()
                try await transport.play(device: device)
                try Task.checkCancellation()
                guard self.sessionID == sessionID else {
                    await mediaProxy.release(resource: preparedResource)
                    return
                }
                activeResource = preparedResource
                candidateResource = nil
                activeDevice = device
                remoteTransportState = "PLAYING"
                state = .playing
                startTransportPolling(for: device, sessionID: sessionID)
            } catch is CancellationError {
                if let candidateResource { await mediaProxy.release(resource: candidateResource) }
                guard self.sessionID == sessionID else { return }
                state = .ready
            } catch {
                if let candidateResource { await mediaProxy.release(resource: candidateResource) }
                guard self.sessionID == sessionID else { return }
                self.activeResource = nil
                activeDevice = nil
                remoteTransportState = nil
                state = .failed(error.localizedDescription)
            }
        }
    }

    func stopCasting() {
        guard let device = activeDevice else {
            pollingTask?.cancel()
            pollingTask = nil
            remoteTransportState = nil
            if let activeResource { Task { await mediaProxy.release(resource: activeResource) } }
            activeResource = nil
            state = .ready
            return
        }
        commandTask?.cancel()
        pollingTask?.cancel()
        pollingTask = nil
        remoteTransportState = nil
        let sessionID = UUID()
        self.sessionID = sessionID
        state = .stopping
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.sessionID == sessionID {
                    activeDevice = nil
                    if let activeResource {
                        Task { await mediaProxy.release(resource: activeResource) }
                    }
                    self.activeResource = nil
                    if case .stopping = state { state = .ready }
                }
            }
            do {
                try await transport.stop(device: device)
            } catch {
                guard self.sessionID == sessionID else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        discoveryID = UUID()
        sessionID = UUID()
        discoveryTask?.cancel()
        commandTask?.cancel()
        pollingTask?.cancel()
        pollingTask = nil
        remoteTransportState = nil
        service.stopDiscovery()
        discoveryTask = nil
        commandTask = nil
    }

    func recoverFromFailure() {
        if devices.isEmpty {
            discover()
        } else {
            state = activeDevice == nil ? .ready : .playing
        }
    }

    private func startTransportPolling(for device: DLNADevice, sessionID: UUID) {
        pollingTask?.cancel()
        let nanoseconds = UInt64(pollInterval * 1_000_000_000)
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }

                guard !Task.isCancelled,
                      self.sessionID == sessionID,
                      self.activeDevice?.id == device.id else { return }

                do {
                    let state = try await self.transport.transportState(device: device)
                    guard !Task.isCancelled,
                          self.sessionID == sessionID,
                          self.activeDevice?.id == device.id else { return }
                    self.applyRemoteTransportState(state)
                } catch is CancellationError {
                    return
                } catch {
                    guard self.sessionID == sessionID else { return }
                    self.pollingTask = nil
                    if let activeResource {
                        Task { await mediaProxy.release(resource: activeResource) }
                    }
                    self.activeResource = nil
                    self.activeDevice = nil
                    self.remoteTransportState = nil
                    self.state = .failed(error.localizedDescription)
                    return
                }
            }
        }
    }

    private func applyRemoteTransportState(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }
        remoteTransportState = normalized

        // A renderer can stop playback without the phone sending Stop (for example
        // when a live stream ends), so release the session when it reports no media.
        if normalized == "STOPPED" || normalized == "NO_MEDIA_PRESENT" {
            pollingTask?.cancel()
            pollingTask = nil
            if let activeResource { Task { await mediaProxy.release(resource: activeResource) } }
            activeResource = nil
            activeDevice = nil
            remoteTransportState = nil
            state = .ready
        }
    }

    var remoteTransportStateLabel: String? {
        guard let remoteTransportState else { return nil }
        switch remoteTransportState {
        case "PLAYING": return "正在播放"
        case "PAUSED_PLAYBACK": return "已暂停"
        case "TRANSITIONING": return "正在切换"
        case "STOPPED", "NO_MEDIA_PRESENT": return "已停止"
        default: return remoteTransportState
        }
    }
}

struct DLNADevicePickerSheet: View {
    let resource: DLNAMediaResource
    @State private var coordinator: DLNACastCoordinator
    @Environment(\.dismiss) private var dismiss

    private let usesFullUI: Bool

    init(resource: DLNAMediaResource, usesFullUI: Bool = false) {
        self.usesFullUI = usesFullUI
        self.resource = resource
        _coordinator = State(initialValue: DLNACastCoordinator())
    }

    var body: some View {
        NavigationStack {
            Group {
                if usesFullUI {
                    List {
                        if showsDeviceList {
                            deviceRows
                        } else {
                            discoveryStatus
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .playerSheetNavigation(Text("DLNA 投屏")) { dismiss() }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("重新搜索设备", systemImage: "arrow.clockwise") { coordinator.discover() }
                                .disabled(coordinator.state.isBusy)
                        }
                    }
                } else {
                    pickerContent
                        .navigationTitle("DLNA 投屏")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("完成") { dismiss() }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    coordinator.discover()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(coordinator.state.isBusy)
                                .accessibilityLabel("重新搜索设备")
                            }
                        }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let activeDevice = coordinator.activeDevice {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("正在投送到 \(activeDevice.friendlyName)", systemImage: "tv.fill")
                                .lineLimit(1)
                            if let status = coordinator.remoteTransportStateLabel {
                                Text(status)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("停止") { coordinator.stopCasting() }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                    .padding()
                    .background(.thinMaterial)
                }
            }
        }
        .task { coordinator.discover() }
        .onDisappear { coordinator.cancel() }
    }

    private var showsDeviceList: Bool {
        if case .failed = coordinator.state { return false }
        return !coordinator.devices.isEmpty
    }

    private var pickerContent: some View {
        Group {
            if showsDeviceList {
                List { deviceRows }.listStyle(.insetGrouped)
            } else {
                discoveryStatus
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var discoveryStatus: some View {
        if coordinator.devices.isEmpty && coordinator.state == .discovering {
            ProgressView("正在搜索局域网设备…")
        } else if case .failed(let message) = coordinator.state {
            ContentUnavailableView {
                Label(
                    coordinator.devices.isEmpty ? "无法发现设备" : "投屏失败",
                    systemImage: "wifi.exclamationmark"
                )
            } description: {
                Text(message)
            } actions: {
                Button(coordinator.devices.isEmpty ? "重新搜索" : "选择其他设备") {
                    coordinator.recoverFromFailure()
                }
            }
        } else if coordinator.devices.isEmpty {
            ContentUnavailableView {
                Label("没有找到 DLNA 设备", systemImage: "tv")
            } description: {
                Text("请确认手机和电视连接到同一个 Wi‑Fi，并在设置中允许 AngelLive 访问本地网络。")
            } actions: {
                Button("重新搜索") { coordinator.discover() }
            }
        }
    }

    private var deviceRows: some View {
        ForEach(coordinator.devices) { device in
            Button {
                coordinator.cast(resource: resource, to: device)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.friendlyName)
                            .foregroundStyle(.primary)
                        if coordinator.activeDevice?.id == device.id {
                            Text(coordinator.remoteTransportStateLabel ?? "正在播放")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if coordinator.activeDevice?.id == device.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(coordinator.state.isBusy)
        }
    }
}
