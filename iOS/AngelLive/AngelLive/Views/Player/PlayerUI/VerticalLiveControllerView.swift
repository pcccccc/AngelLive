//
//  VerticalLiveControllerView.swift
//  AngelLive
//
//  Created by pangchong on 10/31/25.
//

import SwiftUI
import KSPlayer
import AngelLiveCore
import AngelLiveDependencies

/// 竖屏直播专用控制层
/// 设计参考抖音/快手竖屏直播布局
struct VerticalLiveControllerView: View {
    @ObservedObject private var model: KSVideoPlayerModel
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.safeAreaInsetsCustom) private var safeAreaInsets
    @State private var backTapped = false
    @State private var isFavoriteAnimating = false

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { $0.roomId == viewModel.currentRoom.roomId })
    }

    init(model: KSVideoPlayerModel) {
        self.model = model
    }

    var body: some View {
        ZStack {
            // 顶部信息栏
            topBar
                .padding(.top, safeAreaInsets.top)

            // 左下角：弹幕气泡
            bottomLeftArea
                .padding(.bottom, safeAreaInsets.bottom)

            // 右下角：更多按钮
            bottomRightArea
                .padding(.bottom, safeAreaInsets.bottom)
        }
        .opacity(model.config.isMaskShow ? 1 : 0)
    }

    // MARK: - 顶部信息栏

    private var topBar: some View {
        VStack {
            HStack(spacing: 10) {
                // 返回按钮 - iOS 26 Liquid Glass 风格
                Button {
                    backTapped.toggle()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .fontWeight(.medium)
                        .frame(width: 40, height: 40)
                }
                .frame(width: 40, height: 40)
                .adaptiveGlassEffect(in: .rect(cornerRadius: 20.0))

                // 主播信息
                HStack(spacing: 10) {
                    KFImage(URL(string: viewModel.currentRoom.userHeadImg))
                        .placeholder {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(viewModel.currentRoom.userName.prefix(10)))
                            .foregroundStyle(.white)
                            .font(.subheadline.bold())
                            .lineLimit(1)

                        // 直播间热度
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(formatPopularity(viewModel.currentRoom.liveWatchedCount ?? "0"))
                                .foregroundStyle(.white)
                                .font(.caption)
                        }
                    }

                    // 收藏按钮
                    Button {
                        Task {
                            await toggleFavorite()
                        }
                    } label: {
                        Image(systemName: isFavorited ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundStyle(isFavorited ? .red : .white)
                            .frame(width: 28, height: 28)
                            .symbolEffect(.bounce, value: isFavoriteAnimating)
                    }
                    .ksBorderlessButton()
                    .sensoryFeedback(.success, trigger: isFavoriteAnimating)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .adaptiveGlassEffect(in: .circle)
                .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    // MARK: - 左下角区域：弹幕气泡

    private var bottomLeftArea: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    // 弹幕气泡（显示最近6条）- 使用 ChatBubbleView
                    ForEach(viewModel.danmuMessages.suffix(6)) { message in
                        ChatBubbleView(message: message)
                    }
                }

                Spacer()
            }
            .padding(.leading)
        }
    }

    // MARK: - Helper Methods

    /// 格式化热度数值
    private func formatHeat(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", Double(value) / 10000.0)
        } else {
            return "\(value)"
        }
    }

    @MainActor
    private func toggleFavorite() async {
        do {
            if isFavorited {
                try await favoriteModel.removeFavoriteRoom(room: viewModel.currentRoom)
            } else {
                try await favoriteModel.addFavorite(room: viewModel.currentRoom)
            }
            // 触发动画
            isFavoriteAnimating.toggle()
        } catch {
            print("收藏操作失败: \(error)")
        }
    }

    // MARK: - 右下角区域：更多按钮

    private var bottomRightArea: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                MoreActionsButton(
                    onClearChat: {
                        withAnimation {
                            viewModel.danmuMessages.removeAll()
                        }
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
            }
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Glass Effect Extension
private extension View {
    @ViewBuilder
    func adaptiveGlassEffect(in shape: GlassEffectShape) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .rect(let radius):
                self.glassEffect(in: .rect(cornerRadius: radius))
            case .circle:
                self.glassEffect()
            }
        } else {
            switch shape {
            case .rect(let radius):
                self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            case .circle:
                self.background(.ultraThinMaterial, in: Circle())
            }
        }
    }
}

private enum GlassEffectShape {
    case rect(cornerRadius: CGFloat)
    case circle
}
