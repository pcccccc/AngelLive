import Foundation
import Network
import Observation
import Darwin

/// A short-lived, explicitly started LAN download of an already previewed report.
/// Network.framework callbacks run on `.main`; actor hops keep UI state isolated.
@MainActor @Observable
public final class SupportReportSharingService {
    public private(set) var downloadURL: URL?
    public private(set) var errorMessage: String?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var connections: [UUID: NWConnection] = [:]
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var reportData = Data()
    @ObservationIgnored private var reportPath = ""

    public init() {}

    public func start(reportText: String) {
        stop()
        errorMessage = nil
        guard !reportText.isEmpty else {
            errorMessage = "请先生成并预览报告。"
            return
        }
        guard reportText.utf8.count <= 4 * 1_024 * 1_024 else {
            errorMessage = "报告过大，请缩短记录时间后重新生成。"
            return
        }
        guard let address = Self.localIPv4Address() else {
            errorMessage = "未找到局域网地址，请连接 Wi-Fi 或以太网后重试。"
            return
        }
        let generation = UUID()
        self.generation = generation
        reportPath = "/report/\(UUID().uuidString.lowercased()).txt"
        reportData = Data(reportText.utf8)
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(address), port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener?.port else { return }
                        self.errorMessage = nil
                        self.downloadURL = URL(string: "http://\(address):\(port.rawValue)\(self.reportPath)")
                    case .waiting:
                        self.downloadURL = nil
                        self.errorMessage = "正在等待局域网连接，请检查本地网络权限和网络连接。"
                    case .failed:
                        self.stop()
                        self.errorMessage = "无法开启局域网分享，请检查本地网络权限和网络连接后重试。"
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else {
                        connection.cancel()
                        return
                    }
                    self.accept(connection)
                }
            }
            listener.start(queue: .main)
            expiryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                guard let self, self.generation == generation else { return }
                self.stop()
                self.errorMessage = "分享链接已到期，可以重新开启分享。"
            }
        } catch {
            stop()
            errorMessage = "无法开启局域网分享，请检查本地网络权限后重试。"
        }
    }

    public func stop() {
        generation = nil
        expiryTask?.cancel()
        expiryTask = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        for timeout in connectionTimeouts.values { timeout.cancel() }
        connectionTimeouts.removeAll()
        reportData = Data()
        reportPath = ""
        downloadURL = nil
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 4 else {
            connection.cancel()
            return
        }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        connectionTimeouts[id] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self?.close(id)
        }
        receive(id, accumulated: Data())
    }

    private func receive(_ id: UUID, accumulated: Data) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, let connection = self.connections[id] else { return }
                var request = accumulated
                if let data { request.append(data) }
                guard request.count <= 8_192, error == nil else {
                    self.close(id)
                    return
                }
                if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                    let response = SupportReportHTTPResponse.make(
                        request: request, expectedPath: self.reportPath, report: self.reportData
                    )
                    connection.send(content: response, completion: .contentProcessed { [weak self] _ in
                        Task { @MainActor [weak self] in self?.close(id) }
                    })
                } else if complete {
                    self.close(id)
                } else {
                    self.receive(id, accumulated: request)
                }
            }
        }
    }

    private func close(_ id: UUID) {
        connections.removeValue(forKey: id)?.cancel()
        connectionTimeouts.removeValue(forKey: id)?.cancel()
    }

    private static func localIPv4Address() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  String(cString: interface.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host,
                              socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return nil
    }
}

enum SupportReportHTTPResponse {
    static func make(request: Data, expectedPath: String, report: Data) -> Data {
        let firstLine = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let valid = parts.count == 3 && parts[0] == "GET" && parts[1] == expectedPath
            && (parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0") && !expectedPath.isEmpty
        let body = valid ? report : Data("Not found".utf8)
        let status = valid ? "200 OK" : "404 Not Found"
        let attachment = valid ? "Content-Disposition: attachment; filename=\"AngelLive-diagnostics.txt\"\r\n" : ""
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\n\(attachment)Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(body)
        return response
    }
}
