//
//  StreamerInfoView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import UIKit
import AngelLiveCore
import AngelLiveDependencies

/// 使用 UILabel 实现的标题，避免 SwiftUI Text 的自动平衡换行
private struct RoomTitleLabel: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        label.textColor = UIColor(white: 0.95, alpha: 1)
        label.numberOfLines = 2
        label.lineBreakMode = .byCharWrapping
        label.lineBreakStrategy = []
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ uiView: UILabel, context: Context) {
        uiView.text = text
    }
 
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fittingSize = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: fittingSize.height)
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

/// 主播信息视图
struct StreamerInfoView: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.presentToast) private var presentToast
    @State private var isFavoriteAnimating = false
    @State private var showStreamerInfo = false

    /// 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { room in
            if !viewModel.currentRoom.userId.isEmpty, !room.userId.isEmpty {
                return room.liveType == viewModel.currentRoom.liveType && room.userId == viewModel.currentRoom.userId
            }
            return room.liveType == viewModel.currentRoom.liveType && room.roomId == viewModel.currentRoom.roomId
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 直播间标题（置顶，加大加粗）
            RoomTitleLabel(text: viewModel.currentRoom.roomTitle)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 主播信息行
            HStack(spacing: 12) {
                // 主播头像（可点击）
                Button {
                    showStreamerInfo = true
                } label: {
                    KFAnimatedImage(URL(string: viewModel.currentRoom.displayUserHeadImg))
                        .configure { view in
                            view.framePreloadCount = 2
                        }
                        .placeholder {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    // 主播名称
                    Text(viewModel.currentRoom.userName)
                        .font(.headline)
                        .foregroundStyle(Color(white: 0.9))

                    // 人气信息
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text(formatPopularity(viewModel.currentRoom.liveWatchedCount ?? "0"))
                            .font(.caption)
                    }
                    .foregroundStyle(Color(white: 0.7))
                }

                Spacer()

                // 收藏按钮
                Button(action: {
                    Task {
                        await toggleFavorite()
                    }
                }) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(isFavorited ? .red : Color(white: 0.7))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.1))
                        )
                }
                .changeEffect(
                    .spray(origin: UnitPoint(x: 0.5, y: 0.5)) {
                        Image(systemName: isFavorited ? "heart.fill" : "heart.slash.fill")
                            .foregroundStyle(.red)
                    }, value: isFavoriteAnimating
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .sheet(isPresented: $showStreamerInfo) {
            StreamerInfoSheet(room: viewModel.currentRoom)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - 收藏操作

    @MainActor
    private func toggleFavorite() async {
        do {
            if isFavorited {
                try await favoriteModel.removeFavoriteRoom(room: viewModel.currentRoom)
            } else {
                try await favoriteModel.addFavorite(room: viewModel.currentRoom)
            }
            // 成功后触发动画
            isFavoriteAnimating.toggle()
        } catch {
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            let toast = ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: isFavorited ? "取消收藏失败：\(errorMessage)" : "收藏失败：\(errorMessage)"
            )
            presentToast(toast)
            print("收藏操作失败: \(error)")
        }
    }
}
