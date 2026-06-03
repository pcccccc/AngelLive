//
//  LiveRoomCard.swift
//  AngelLive
//
//  Created by pangchong on 10/20/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 卡片点击时的直播状态检查策略
enum LiveCheckMode {
    /// 直接进入，不判断（房间列表 — 都是在播的）
    case none
    /// 用本地 liveState 判断（收藏、搜索）
    case local
    /// 异步请求 API 查询（历史记录）
    case remote
}

struct LiveRoomCard: View {
    let room: LiveModel
    let liveCheckMode: LiveCheckMode
    let showsCoverBadge: Bool
    /// 可选的删除回调（用于历史记录）
    var onDelete: (() -> Void)? = nil
    /// 是否禁用 SwiftUI 自身的 tap gesture(由 cell 设置为 true)。
    /// hostingView 内的 SwiftUI gesture recognizer 跟 UICollectionView 自己的 tap recognizer 会竞争,
    /// 在 UIHostingController-in-cell 这种场景下 SwiftUI 经常输,导致两个都不触发。
    /// cell-based 路径(RoomList/Favorite/History)由 UICollectionView 的 didSelectItemAt 接管 tap。
    var disableTapGesture: Bool = false
    /// 本地导航状态 - 仅在没有外部导航状态时使用
    @State private var localShowPlayer = false
    /// 本地 Namespace - 仅在没有外部 Namespace 时使用
    @Namespace private var localNamespace
    /// 正在查询直播状态中
    @State private var isCheckingLiveState = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppFavoriteModel.self) private var favoriteModel
    @Environment(\.presentToast) private var presentToast
    /// 外部导航状态 - 用于解决 PiP 导航状态丢失问题
    @Environment(\.liveRoomNavigationState) private var externalNavigationState
    /// 外部 Namespace - 用于保持 zoom 过渡动画
    @Environment(\.roomTransitionNamespace) private var externalNamespace

    /// 使用外部 Namespace（如果有），否则使用本地
    private var namespace: Namespace.ID {
        externalNamespace ?? localNamespace
    }

    /// 是否使用外部导航（外部状态存在时使用外部导航）
    private var useExternalNavigation: Bool {
        externalNavigationState != nil
    }

    /// 导航绑定 - 使用外部状态或本地状态
    private var showPlayerBinding: Binding<Bool> {
        if let state = externalNavigationState {
            return Binding(
                get: { state.showPlayer && state.currentRoom?.roomId == room.roomId },
                set: { newValue in
                    if newValue {
                        state.navigate(to: room)
                    } else if state.currentRoom?.roomId == room.roomId {
                        state.dismiss()
                    }
                }
            )
        } else {
            return $localShowPlayer
        }
    }

    private var coverURL: URL? {
        guard !room.roomCover.isEmpty, let url = URL(string: room.roomCover) else { return nil }
        return url
    }

    private var avatarURL: URL? {
        guard !room.userHeadImg.isEmpty, let url = URL(string: room.userHeadImg) else { return nil }
        return url
    }

    init(room: LiveModel, width: CGFloat? = nil, liveCheckMode: LiveCheckMode = .local, showsCoverBadge: Bool = false) {
        self.room = room
        self.liveCheckMode = liveCheckMode
        self.showsCoverBadge = showsCoverBadge
    }

    // 判断是否已收藏
    private var isFavorited: Bool {
        favoriteModel.roomList.contains(where: { item in
            if !room.userId.isEmpty, !item.userId.isEmpty {
                return item.liveType == room.liveType && item.userId == room.userId
            }
            return item.liveType == room.liveType && item.roomId == room.roomId
        })
    }

    // 判断是否正在直播
    // liveState 为 nil 或无法解析时视为在播（房间列表本身就是在播列表）
    // 只有明确为 close("0") 时才判定下播
    private var isLive: Bool {
        guard let liveState = room.liveState,
              let state = LiveState(rawValue: liveState) else { return true }
        return state != .close
    }

    // TODO: 平台图标和直播状态暂时隐藏，待重新设计后恢复
//    private var badgeLiveState: LiveState {
//        guard let liveState = room.liveState, let state = LiveState(rawValue: liveState) else {
//            return .live
//        }
//        return state
//    }
//
//    private var liveStatusText: String {
//        switch badgeLiveState {
//        case .live:
//            return "直播中"
//        case .close:
//            return "已下播"
//        case .video:
//            return "回放中"
//        case .unknow:
//            return "待确认"
//        }
//    }

    var body: some View {
        Group {
            // disableTapGesture=true 时不挂 onTapGesture,把 tap 让给外层 UICollectionView 的 didSelectItemAt
            // (cell-based 场景 SwiftUI gesture 跟 UICollectionView tap 抢路会两边都不触发)。
            let baseContent = cardContent
                .overlay {
                    if isCheckingLiveState {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg)
                                .fill(.black.opacity(0.3))
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
                .contentShape(Rectangle())

            let baseTappable = Group {
                if disableTapGesture {
                    baseContent
                } else {
                    baseContent.onTapGesture { handleTap() }
                }
            }
            .contextMenu {
                favoriteContextMenu
            }

            if useExternalNavigation {
                baseTappable
            } else {
                if #available(iOS 18.0, *) {
                    baseTappable
                        .fullScreenCover(isPresented: showPlayerBinding) {
                            DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: namespace))
                                .toolbar(.hidden, for: .tabBar)
                        }
                } else {
                    baseTappable
                        .navigationDestination(isPresented: showPlayerBinding) {
                            DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: namespace))
                                .toolbar(.hidden, for: .tabBar)
                        }
                }
            }
        }
    }

    private func handleTap() {
        switch liveCheckMode {
        case .none:
            // 房间列表：直接进入，不判断
            showPlayerBinding.wrappedValue = true
        case .local:
            // 收藏/搜索：用本地 liveState 判断
            if isLive {
                showPlayerBinding.wrappedValue = true
            } else {
                presentToast(ToastValue(icon: Image(systemName: "tv.slash"), message: "主播已下播"))
            }
        case .remote:
            // 历史记录：异步请求 API 查询直播状态
            guard !isCheckingLiveState else { return }
            Task {
                isCheckingLiveState = true
                defer { isCheckingLiveState = false }
                do {
                    let state = try await ApiManager.getCurrentRoomLiveState(
                        roomId: room.roomId,
                        userId: room.userId,
                        liveType: room.liveType
                    )
                    if state == .live {
                        showPlayerBinding.wrappedValue = true
                    } else {
                        presentToast(ToastValue(icon: Image(systemName: "tv.slash"), message: "主播已下播"))
                    }
                } catch {
                    // 查询失败仍放行，让播放页自行处理
                    showPlayerBinding.wrappedValue = true
                }
            }
        }
    }

    private var cardContent: some View {
        VStack {
            // 封面图（带可靠的兜底占位）
            coverView
                // TODO: 平台图标和直播状态暂时隐藏，待重新设计后恢复
//                .overlay(alignment: .topTrailing) {
//                    if showsCoverBadge {
//                        coverInfoBadge
//                            .padding(6)
//                    }
//                }
                .cornerRadius(AppConstants.CornerRadius.lg)
                .clipped()
                .modifier(MatchedTransitionSourceModifier(id: room.roomId, namespace: namespace))

            // 主播信息
            HStack(spacing: 8) {
                avatarView
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(room.roomTitle.orDash)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppConstants.Colors.primaryText)
                        .lineLimit(1)

                    Text(room.userName.orDash)
                        .font(.caption)
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - 子视图

    // TODO: 平台图标和直播状态暂时隐藏，待重新设计后恢复
//    private var coverInfoBadge: some View {
//        HStack(spacing: 6) {
//            platformBadgeIcon
//
//            Text(liveStatusText)
//                .font(.caption2.weight(.medium))
//                .foregroundStyle(.white)
//                .lineLimit(1)
//        }
//        .padding(.horizontal, 7)
//        .padding(.vertical, 4)
//        .background(Color.black.opacity(0.58))
//        .clipShape(Capsule(style: .continuous))
//    }
//
//    @ViewBuilder
//    private var platformBadgeIcon: some View {
//        if let image = PlatformIconProvider.tabImage(for: room.liveType) {
//            Image(uiImage: image)
//                .resizable()
//                .scaledToFit()
//                .frame(width: 12, height: 12)
//                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
//        } else {
//            Image(systemName: "dot.radiowaves.left.and.right")
//                .font(.caption2.weight(.bold))
//                .foregroundStyle(.white.opacity(0.92))
//                .frame(width: 12, height: 12)
//        }
//    }

    /// 封面图容器：有 URL 时双层 KFImage（模糊背景 + 清晰前景，不变形），失败或无 URL 时用本地占位
    private var coverView: some View {
        Group {
            if let url = coverURL {
                // 背景模糊层：模糊在缓存时预处理，避免滚动时 GPU 实时模糊（减少 offscreen passes）
                KFImage(url)
                    .setProcessor(
                        DownsamplingImageProcessor(size: CGSize(width: 80, height: 45))
                        |> BlurImageProcessor(blurRadius: 8)
                    )
                    .placeholder {
                        Rectangle()
                            .fill(AppConstants.Colors.placeholderGradient())
                    }
                    .resizable()
                    .overlay(
                        // 前景清晰层：保持原比例居中显示，不变形
                        KFImage(url)
                            .placeholder {
                                placeholderCover()
                            }
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    )
            } else {
                placeholderCover()
            }
        }
    }

    /// 头像：无效 URL 时展示占位
    private var avatarView: some View {
        Group {
            if let url = avatarURL {
                KFImage(url)
                    .placeholder { avatarPlaceholder }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                avatarPlaceholder
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    private func placeholderCover() -> some View {
        ZStack {
            Rectangle()
                .fill(AppConstants.Colors.placeholderGradient())
            Image("placeholder")
                .resizable()
                .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
                .opacity(0.7)
        }
        .aspectRatio(AppConstants.AspectRatio.pic, contentMode: .fit)
    }

    @ViewBuilder
    private var favoriteContextMenu: some View {
        if isFavorited {
            Button(role: .destructive) {
                Task {
                    await removeFavorite()
                }
            } label: {
                Label("取消收藏", systemImage: "heart.slash.fill")
            }
        } else {
            Button {
                Task {
                    await addFavorite()
                }
            } label: {
                Label("收藏", systemImage: "heart.fill")
            }
        }

        // 删除历史记录选项（仅在提供 onDelete 回调时显示）
        if let onDelete = onDelete {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
    }

    @MainActor
    private func addFavorite() async {
        do {
            try await favoriteModel.addFavorite(room: room)

            // 本地优先:收藏已成功;若云端同步失败,非阻塞提示原因+码。
            if favoriteModel.favoriteICloudSyncEnabled, let syncError = favoriteModel.lastSyncError {
                presentToast(ToastValue(
                    icon: Image(systemName: "icloud.slash"),
                    message: "已收藏 · iCloud 同步失败：\(syncError.displayText)"
                ))
            } else {
                presentToast(ToastValue(icon: Image(systemName: "heart.fill"), message: "收藏成功"))
            }
        } catch {
            // 显示失败提示
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            let toast = ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: "收藏失败：\(errorMessage)"
            )
            presentToast(toast)
            print("收藏失败: \(error)")
        }
    }

    @MainActor
    private func removeFavorite() async {
        do {
            try await favoriteModel.removeFavoriteRoom(room: room)

            if favoriteModel.favoriteICloudSyncEnabled, let syncError = favoriteModel.lastSyncError {
                presentToast(ToastValue(
                    icon: Image(systemName: "icloud.slash"),
                    message: "已取消收藏 · iCloud 同步失败：\(syncError.displayText)"
                ))
            } else {
                presentToast(ToastValue(icon: Image(systemName: "heart.slash.fill"), message: "已取消收藏"))
            }
        } catch {
            // 显示失败提示
            let errorMessage = FavoriteService.formatErrorCode(error: error)
            let toast = ToastValue(
                icon: Image(systemName: "xmark.circle.fill"),
                message: "取消收藏失败：\(errorMessage)"
            )
            presentToast(toast)
            print("取消收藏失败: \(error)")
        }
    }
}

/// 直播间卡片按钮样式 - 提供按压缩放效果
struct LiveRoomCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}
