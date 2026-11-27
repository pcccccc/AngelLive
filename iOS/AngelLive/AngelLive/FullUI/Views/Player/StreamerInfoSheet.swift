//
//  StreamerInfoSheet.swift
//  AngelLive
//
//  Created by pangchong on 12/26/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import Kingfisher

/// 主播详细信息弹窗
struct StreamerInfoSheet: View {
    let room: LiveModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentToast) private var presentToast
    @Environment(\.openURL) private var openURL
    @State private var translationSettings = RoomTranslationSettings.shared
    @State private var translationService = RoomTitleTranslationService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerSection
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                roomInfoSection
                Section {
                    Button("复制直播间链接", systemImage: "doc.on.doc", action: copyLink)
                        .foregroundStyle(.primary)
                    Button("在浏览器中打开", systemImage: "safari", action: openInBrowser)
                        .foregroundStyle(.primary)
                        .disabled(room.liveType.roomURL(roomId: room.roomId, userId: room.userId) == nil)
                }
            }
            .listStyle(.insetGrouped)
            .roomTitleTranslationTask(room.roomTitle)
            .playerSheetNavigation(Text("主播信息")) { dismiss() }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // 主播头像
            if let avatarURL = URL(string: room.userHeadImg), !room.userHeadImg.isEmpty {
                KFAnimatedImage(avatarURL)
                    .configure { view in
                        view.framePreloadCount = 2
                    }
                    .placeholder {
                        Circle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(.quaternary, lineWidth: 2)
                    }
            } else {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
            }

            // 主播名称
            Text(room.userName.orDash)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            // 平台标签
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

    // MARK: - Room Info Section

    private var roomInfoSection: some View {
        Section("直播间信息") {
            LabeledContent("原始标题", value: room.roomTitle.orDash)
            if translatedTitle != nil {
                LabeledContent("译文") { TranslatedRoomTitle(room.roomTitle.orDash) }
            }
            LabeledContent("房间号", value: room.roomId)
            if let count = room.liveWatchedCount, !count.isEmpty {
                LabeledContent("观看人数", value: count)
            }
        }
    }

    private var translatedTitle: String? {
        guard translationSettings.isEnabled else { return nil }
        let translated = translationService.displayTitle(for: room.roomTitle)
        guard translated != room.roomTitle else { return nil }
        return translated
    }

    // MARK: - Actions

    private func copyLink() {
        guard let url = room.liveType.roomURL(roomId: room.roomId, userId: room.userId) else {
            presentToast(ToastValue(icon: Image(systemName: "exclamationmark.triangle.fill"), message: "当前资源未提供外部链接"))
            return
        }
        UIPasteboard.general.string = url.absoluteString

        let toast = ToastValue(
            icon: Image(systemName: "checkmark.circle.fill"),
            message: "链接已复制"
        )
        presentToast(toast)
    }

    private func openInBrowser() {
        if let url = room.liveType.roomURL(roomId: room.roomId, userId: room.userId) {
            openURL(url)
        }
    }
}

// MARK: - LiveType Extension

extension LiveType {
    /// 平台名称
    var platformName: String {
        LiveParseTools.getLivePlatformName(self)
    }

    /// 平台主题色
    var platformColor: Color {
        if let hex = PlatformHostBehavior.themeColorHex(for: self),
           let color = Color(hex: hex) {
            return color
        }
        return Color.generated(from: rawValue)
    }

    /// 获取原平台直播间链接
    func roomURL(roomId: String, userId: String) -> URL? {
        PlatformHostBehavior.externalRoomURL(for: self, roomId: roomId, userId: userId)
    }
}

private extension Color {
    init?(hex: String) {
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

#Preview {
    StreamerInfoSheet(
        room: LiveModel(
            userName: "测试主播",
            roomTitle: "今天来玩游戏！",
            roomCover: "",
            userHeadImg: "",
            liveType: .placeholder,
            liveState: "1",
            userId: "12345",
            roomId: "67890",
            liveWatchedCount: "1.2万"
        )
    )
}
