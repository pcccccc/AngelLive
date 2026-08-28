import Foundation
import Network

/// 系统路径只提供“明确断网”提示和变化代际，不证明任一插件可达。
public actor NetworkPathObserver: FavoriteNetworkPathObserving {
    public static let shared = NetworkPathObserver()

    private let monitor: NWPathMonitor
    private var status: FavoriteNetworkPathStatus = .unknown
    private var revision: UInt64 = 0

    public init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let nextStatus: FavoriteNetworkPathStatus
            switch path.status {
            case .satisfied:
                nextStatus = .satisfied
            case .unsatisfied:
                nextStatus = .unsatisfied
            case .requiresConnection:
                nextStatus = .requiresConnection
            @unknown default:
                nextStatus = .unknown
            }
            Task { await self?.accept(nextStatus) }
        }
        monitor.start(queue: DispatchQueue(label: "angellive.favorite.network-path"))
    }

    deinit {
        monitor.cancel()
    }

    public func currentStatus() async -> FavoriteNetworkPathStatus {
        status
    }

    public func currentRevision() async -> UInt64 {
        revision
    }

    private func accept(_ nextStatus: FavoriteNetworkPathStatus) {
        guard status != nextStatus else { return }
        status = nextStatus
        revision &+= 1
    }
}
