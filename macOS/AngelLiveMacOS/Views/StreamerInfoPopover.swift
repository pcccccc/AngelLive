//
//  StreamerInfoPopover.swift
//  AngelLiveMacOS
//
//  Created by pangchong on 5/25/26.
//

import SwiftUI
import AppKit
import AngelLiveCore
import AngelLiveDependencies

/// 主播详细信息弹窗（macOS Popover 形态，对应 iOS 的 StreamerInfoSheet）
struct StreamerInfoPopover: View {
    let room: LiveModel
    @Environment(\.openURL) private var openURL
    @Environment(ToastManager.self) private var toastManager: ToastManager?

    var body: some View {
        VStack(spacing: 20) {
            headerSection

            roomInfoSection

            actionButtons
        }
        .padding(20)
        .frame(width: 340)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
            RemoteAvatarView(url: URL(string: room.userHeadImg), size: 72) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "person.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(14)
                    )
            }
            .overlay(
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )

            Text(room.userName.orDash)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)

            platformBadge
        }
    }

    private var platformBadge: some View {
        Text(room.liveType.platformName)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(room.liveType.platformColor, in: Capsule())
    }

    // MARK: - Room Info

    private var roomInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(icon: "tv", title: "直播间标题", value: room.roomTitle.orDash)

            Divider()

            infoRow(icon: "number", title: "房间号", value: room.roomId.orDash)

            if let watched = room.liveWatchedCount, !watched.isEmpty {
                Divider()
                infoRow(icon: "eye", title: "观看人数", value: watched)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .layoutPriority(0)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                copyLink()
            } label: {
                Label("复制直播间链接", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .tint(.blue)
            .disabled(externalURL == nil)

            Button {
                openInBrowser()
            } label: {
                Label("在浏览器中打开", systemImage: "safari")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(room.liveType.platformColor)
            .disabled(externalURL == nil)
        }
    }

    // MARK: - Helpers

    private var externalURL: URL? {
        room.liveType.roomURL(roomId: room.roomId, userId: room.userId)
    }

    private func copyLink() {
        guard let url = externalURL else {
            toastManager?.show(icon: "exclamationmark.triangle.fill",
                               message: "当前资源未提供外部链接",
                               type: .error)
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        toastManager?.show(icon: "checkmark.circle.fill", message: "链接已复制", type: .success)
    }

    private func openInBrowser() {
        if let url = externalURL {
            openURL(url)
        }
    }
}

// MARK: - LiveType helpers (macOS)

extension LiveType {
    /// 平台名称
    var platformName: String {
        LiveParseTools.getLivePlatformName(self)
    }

    /// 平台主题色
    var platformColor: Color {
        if let hex = PlatformHostBehavior.themeColorHex(for: self),
           let color = Color(macHex: hex) {
            return color
        }
        return Color.generated(from: rawValue)
    }

    /// 原平台直播间链接
    func roomURL(roomId: String, userId: String) -> URL? {
        PlatformHostBehavior.externalRoomURL(for: self, roomId: roomId, userId: userId)
    }
}

private extension Color {
    init?(macHex hex: String) {
        var normalized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        guard let value = UInt64(normalized, radix: 16) else { return nil }
        switch normalized.count {
        case 6:
            self.init(
                red: Double((value >> 16) & 0xff) / 255,
                green: Double((value >> 8) & 0xff) / 255,
                blue: Double(value & 0xff) / 255
            )
        case 8:
            self.init(
                red: Double((value >> 16) & 0xff) / 255,
                green: Double((value >> 8) & 0xff) / 255,
                blue: Double(value & 0xff) / 255,
                opacity: Double((value >> 24) & 0xff) / 255
            )
        default:
            return nil
        }
    }

    static func generated(from seed: String) -> Color {
        let scalars = seed.unicodeScalars.map(\.value)
        let hash = scalars.reduce(UInt32(2166136261)) { ($0 ^ $1) &* 16777619 }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.78)
    }
}
