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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 主播头像和基本信息
                    headerSection

                    // 直播间信息
                    roomInfoSection

                    // 操作按钮
                    actionButtons

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(.ultraThinMaterial)
            .navigationTitle("主播信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // 主播头像
            if let avatarURL = URL(string: room.userHeadImg), !room.userHeadImg.isEmpty {
                KFImage(avatarURL)
                    .resizable()
                    .placeholder {
                        Circle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                            }
                    }
                    .scaledToFill()
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
            Text(room.userName)
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
        VStack(alignment: .leading, spacing: 16) {
            // 直播间标题
            infoRow(icon: "tv", title: "直播间标题", value: room.roomTitle)

            Divider()

            // 房间号
            infoRow(icon: "number", title: "房间号", value: room.roomId)

            if let watchedCount = room.liveWatchedCount, !watchedCount.isEmpty {
                Divider()
                // 观看人数
                infoRow(icon: "eye", title: "观看人数", value: watchedCount)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 复制链接按钮
            Button {
                copyLink()
            } label: {
                Label("复制直播间链接", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            // 跳转到原平台
            Button {
                openInBrowser()
            } label: {
                Label("在浏览器中打开", systemImage: "safari")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(room.liveType.platformColor)
        }
    }

    // MARK: - Actions

    private func copyLink() {
        let link = room.liveType.getRoomURL(roomId: room.roomId, userId: room.userId)
        UIPasteboard.general.string = link

        let toast = ToastValue(
            icon: Image(systemName: "checkmark.circle.fill"),
            message: "链接已复制"
        )
        presentToast(toast)
    }

    private func openInBrowser() {
        let link = room.liveType.getRoomURL(roomId: room.roomId, userId: room.userId)
        if let url = URL(string: link) {
            openURL(url)
        }
    }
}

// MARK: - LiveType Extension

extension LiveType {
    /// 平台名称
    var platformName: String {
        switch self {
        case .bilibili: return "哔哩哔哩"
        case .huya: return "虎牙"
        case .douyin: return "抖音"
        case .douyu: return "斗鱼"
        case .cc: return "网易CC"
        case .ks: return "快手"
        case .yy: return "YY"
        case .youtube: return "YouTube"
        }
    }

    /// 平台主题色
    var platformColor: Color {
        switch self {
        case .bilibili: return Color(red: 0.98, green: 0.45, blue: 0.55) // 粉色
        case .huya: return Color(red: 1.0, green: 0.6, blue: 0.0) // 橙色
        case .douyin: return Color(red: 0.0, green: 0.0, blue: 0.0) // 黑色
        case .douyu: return Color(red: 1.0, green: 0.5, blue: 0.0) // 橙色
        case .cc: return Color(red: 0.98, green: 0.75, blue: 0.18) // 黄色
        case .ks: return Color(red: 1.0, green: 0.35, blue: 0.0) // 橙红
        case .yy: return Color(red: 1.0, green: 0.8, blue: 0.0) // 黄色
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0) // 红色
        }
    }

    /// 获取原平台直播间链接
    func getRoomURL(roomId: String, userId: String) -> String {
        switch self {
        case .bilibili:
            return "https://live.bilibili.com/\(roomId)"
        case .huya:
            return "https://www.huya.com/\(roomId)"
        case .douyin:
            return "https://live.douyin.com/\(roomId)"
        case .douyu:
            return "https://www.douyu.com/\(roomId)"
        case .cc:
            return "https://cc.163.com/\(roomId)"
        case .ks:
            // 快手使用 userId
            return "https://live.kuaishou.com/u/\(userId)"
        case .yy:
            return "https://www.yy.com/\(roomId)"
        case .youtube:
            return "https://www.youtube.com/watch?v=\(roomId)"
        }
    }
}

#Preview {
    StreamerInfoSheet(
        room: LiveModel(
            userName: "测试主播",
            roomTitle: "今天来玩游戏！",
            roomCover: "",
            userHeadImg: "",
            liveType: .bilibili,
            liveState: "1",
            userId: "12345",
            roomId: "67890",
            liveWatchedCount: "1.2万"
        )
    )
}
