import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct MacDLNADevicePickerSheet: View {
    let session: DLNACastingSession
    let resource: DLNAMediaResource?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceContent
            if session.state == .settingURI || session.activeDevice != nil {
                Divider()
                castStatus
            }
        }
        .macSettingsPage("DLNA 投屏") {
            Button("重新搜索", systemImage: "arrow.clockwise") { session.discover() }
                .disabled(session.state.isBusy)
        }
        .macSettingsSheetPresentation()
        .frame(minWidth: 440, idealWidth: 480, minHeight: 340, idealHeight: 400)
        .task {
            if session.state == .idle || session.state == .ready || session.state == .playing {
                session.discover()
            }
        }
        .onDisappear { session.cancelDiscovery() }
    }

    private var deviceContent: some View {
        VStack(spacing: 0) {
            if !session.devices.isEmpty {
                if case .failed(let message) = session.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 16)
                }
                List(session.devices) { device in
                    deviceRow(device)
                }
                .listStyle(.inset)
            } else if session.state == .idle || session.state == .discovering {
                ProgressView("正在搜索局域网设备…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .failed(let message) = session.state {
                ContentUnavailableView("未找到 DLNA 设备", systemImage: "tv.slash", description: Text(message))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.state != .settingURI {
                ContentUnavailableView(
                    "没有找到 DLNA 设备",
                    systemImage: "tv",
                    description: Text("请确认 Mac 和电视连在同一个局域网，并允许 AngelLive 访问本地网络。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
    }

    private func deviceRow(_ device: DLNADevice) -> some View {
        let isActive = session.activeDevice?.id == device.id
        return Button {
            guard let resource else { return }
            session.cast(resource: resource, to: device)
        } label: {
            HStack(spacing: 12) {
                Label(device.friendlyName, systemImage: "tv")
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppConstants.Colors.accent)
                        .accessibilityLabel("正在投屏")
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.state.isBusy || resource == nil)
    }

    private var castStatus: some View {
        HStack(spacing: 12) {
            if session.state == .settingURI {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("正在连接设备…")
            } else if let activeDevice = session.activeDevice {
                VStack(alignment: .leading, spacing: 4) {
                    Label("正在投屏到 \(activeDevice.friendlyName)", systemImage: "tv.fill")
                        .lineLimit(1)
                    Text(transportStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("停止投屏", role: .destructive) { session.stopCasting() }
                    .disabled(session.state == .stopping)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var transportStatus: LocalizedStringKey {
        if session.state == .stopping { return "正在停止…" }
        switch session.remoteTransportState {
        case "PLAYING": return "正在播放"
        case "PAUSED_PLAYBACK": return "已暂停"
        case "TRANSITIONING": return "正在切换"
        default: return "已连接"
        }
    }
}
