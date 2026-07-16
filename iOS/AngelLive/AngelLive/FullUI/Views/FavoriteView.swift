//
//  FavoriteView.swift
//  AngelLive
//
//  收藏列表 - 使用 UICollectionView 实现
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import UIKit

struct FavoriteView: View {
    @Environment(AppFavoriteModel.self) private var viewModel
    @State private var searchText = ""
    /// 共享导航状态 - 在 PiP 背景/前台切换时保持稳定
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace
    private static var lastLeaveTimestamp: Date?
    private static let syncCooldown: TimeInterval = 180

    var body: some View {
        playerPresentation
            // 同步提示条挂在最外层(安全区正常),贴合灵动岛/刘海下方,不受列表 ignoresSafeArea 影响
            .overlay(alignment: .top) { syncBannerOverlay }
            .animation(.easeInOut(duration: 0.25), value: viewModel.isCloudSyncing)
            .searchable(text: $searchText, prompt: "搜索主播名或房间标题")
            .task {
                await loadIfNeeded()
            }
            .onDisappear {
                FavoriteView.lastLeaveTimestamp = Date()
            }
    }

    @ViewBuilder
    private var playerPresentation: some View {
        if #available(iOS 18.0, *) {
            baseNavigation
                .fullScreenCover(isPresented: playerPresentedBinding) {
                    playerDestination
                }
        } else {
            // iOS 17: navigationDestination 必须在 NavigationStack 内部
            NavigationStack {
                favoriteList
                    .navigationDestination(isPresented: playerPresentedBinding) {
                        playerDestination
                    }
            }
        }
    }

    private var baseNavigation: some View {
        NavigationStack {
            favoriteList
        }
    }

    /// 收藏列表主体(UIKit 集合视图包装 + 安全区域/大标题处理),iOS 17/18 共用。
    private var favoriteList: some View {
        FavoriteListViewControllerWrapper(
            searchText: searchText,
            navigationState: navigationState,
            namespace: roomTransitionNamespace
        )
        // 安全区域处理 - 同时支持 TabBar 透视和大标题动画
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 0) }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 0) }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .navigationTitle("收藏")
        .navigationBarTitleDisplayMode(.large)
    }

    /// 同步提示条,不拦截触摸。按顶部形态分流:
    /// - 灵动岛:A — 金属球「有丝分裂」液态动画(几何锚在岛上,只对灵动岛成立)。
    /// - 刘海 / Home 键 / iPad:降级为普通同步胶囊,从安全区顶部下滑(不写死岛坐标)。
    /// 形态由 DeviceTopSensor 依顶部安全区高度判定,新机型自动通吃,无需机型白名单。
    @ViewBuilder
    private var syncBannerOverlay: some View {
        switch DeviceTopSensor.current {
        case .dynamicIsland:
            IslandSyncBanner(active: viewModel.isCloudSyncing)
                .allowsHitTesting(false)
        case .notch, .none:
            PlainSyncBanner(active: viewModel.isCloudSyncing)
                .allowsHitTesting(false)
        }
    }

    private var playerPresentedBinding: Binding<Bool> {
        Binding(
            get: { navigationState.showPlayer },
            set: { navigationState.showPlayer = $0 }
        )
    }

    @ViewBuilder
    private var playerDestination: some View {
        if let room = navigationState.currentRoom {
            DetailPlayerView(
                viewModel: RoomInfoViewModel(room: room),
                categoryRooms: navigationState.categoryRooms
            )
                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: roomTransitionNamespace))
                .toolbar(.hidden, for: .tabBar)
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        if shouldSkipSyncAfterReturn() {
            return
        }
        if viewModel.shouldSync() {
            await viewModel.syncWithActor()
        }
    }

    private func shouldSkipSyncAfterReturn() -> Bool {
        guard let lastLeave = FavoriteView.lastLeaveTimestamp else {
            return false
        }
        let timeSinceLeave = Date().timeIntervalSince(lastLeave)
        return timeSinceLeave < FavoriteView.syncCooldown
    }
}

// MARK: - B:常驻美化胶囊(和同步无关,一直贴在灵动岛下方)

/// 灵动岛下方常驻的品牌/美化胶囊,截图更好看。与同步状态无关。
/// 用满屏容器建立「屏幕顶部 = y0」坐标(与同步动画一致),再把顶边塞进岛底,与岛连体。
struct IslandDecorPill: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                Text("AngelLive")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule(style: .continuous).fill(Color.accentColor.gradient))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            .offset(y: 38)   // 顶边塞进灵动岛底(岛底约 y48),下半截露出,看起来与岛连体
        }
        .ignoresSafeArea()
    }
}

// MARK: - A:同步液态动画(仅同步时落下,待机隐藏)

/// 灵动岛「有丝分裂」液态同步动画。仅同步进行中(active)才从岛里落下展示;待机完全隐藏。
struct IslandSyncBanner: View {
    let active: Bool

    @State private var drop: CGFloat = 0   // 0 = 缩在岛内, 1 = 完全落下

    var body: some View {
        Group {
            if active || drop > 0.001 {
                MetaballBanner(drop: drop)
            }
        }
        .ignoresSafeArea()
        .onAppear { if active { animate(to: 1) } }
        .onChange(of: active) { _, now in animate(to: now ? 1 : 0) }
    }

    private func animate(to value: CGFloat) {
        // 落下:弹性带过冲(水滴回弹);缩回:平滑
        let anim: Animation = value >= 1
            ? .bouncy(duration: 0.6, extraBounce: 0.22)
            : .smooth(duration: 0.4)
        withAnimation(anim) { drop = value }
    }
}

// MARK: - A':非灵动岛机型的降级同步胶囊(刘海 / Home 键 / iPad)

/// 金属球「从岛里长出」的几何只对灵动岛成立;其余机型改用普通胶囊,从安全区顶部下滑。
/// 视觉沿用金属球版(深色渐变 + 旋转图标 + 文案),不写死任何岛/刘海坐标。
struct PlainSyncBanner: View {
    let active: Bool

    @State private var spin = false

    var body: some View {
        Group {
            if active {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                    Text("正在同步收藏")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.17), Color(white: 0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
                .padding(.top, 8)   // 落在安全区顶部下方一点(状态栏/导航栏之下)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                        spin = true
                    }
                }
            }
        }
    }
}

/// 金属球胶囊本体。遵循 Animatable,使 `drop` 在动画事务中逐帧插值。
/// 液态感:弹性过冲 + 下坠中段表面张力「拉长成水滴」+ 落地「压扁回弹」。
private struct MetaballBanner: View, Animatable {
    var drop: CGFloat
    var animatableData: CGFloat {
        get { drop }
        set { drop = newValue }
    }

    private let anchorWidth: CGFloat = 78
    private let anchorHeight: CGFloat = 16
    private let islandCenterY: CGFloat = 27
    private let islandBottom: CGFloat = 48
    private let pillWidth: CGFloat = 176
    private let pillHeight: CGFloat = 40
    private let gap: CGFloat = 16

    private var fall: CGFloat { min(1, max(0, drop)) }
    private var over: CGFloat { max(0, drop - 1) }
    private var dip: CGFloat { min(drop, 1.14) }
    private var stretch: CGFloat { CGFloat(sin(Double.pi * Double(fall))) }

    private var pillCenterY: CGFloat {
        let target = islandBottom + gap + pillHeight / 2
        return islandCenterY + (target - islandCenterY) * dip
    }
    private var pillW: CGFloat {
        let base = anchorWidth + (pillWidth - anchorWidth) * fall
        return max(anchorWidth, base * (1 - 0.16 * stretch + 1.5 * over))
    }
    private var pillH: CGFloat {
        let base = anchorHeight + (pillHeight - anchorHeight) * fall
        return max(anchorHeight, base * (1 + 0.34 * stretch - 1.7 * over))
    }
    private var contentOpacity: Double { Double(min(1, max(0, (fall - 0.6) / 0.32))) }

    @State private var spin = false

    var body: some View {
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let cx = geo.size.width / 2
            ZStack(alignment: .top) {
                liquidBody(height: h, centerX: cx)
                content
            }
        }
    }

    /// 融球本体:整块深色渐变被「岛内锚点 + 下落胶囊」的融球剪影裁出。
    /// 于是脖子拉丝、有丝分裂、落地压扁全程都带真实渐变色;顶部渐变收黑,
    /// 贴着灵动岛那截与岛无缝融为一体(不再是盖在黑剪影上的纯色胶囊)。
    private func liquidBody(height h: CGFloat, centerX cx: CGFloat) -> some View {
        let topY = islandCenterY - anchorHeight / 2
        let botY = pillCenterY + pillH / 2
        let span = max(1, botY - topY)
        // 胶囊顶在整段融球里的纵向占比 → 渐变提亮点随下落逐帧上移,拉丝段自然由黑转亮。
        let pillTopFrac = min(0.92, max(0.06, (pillCenterY - pillH / 2 - topY) / span))
        return LinearGradient(
            stops: [
                .init(color: Color(white: 0.0), location: 0),            // 岛内:纯黑,与灵动岛融合
                .init(color: Color(white: 0.17), location: pillTopFrac), // 胶囊顶:提亮
                .init(color: Color(white: 0.03), location: 1)            // 胶囊底:收深
            ],
            startPoint: UnitPoint(x: 0.5, y: topY / h),
            endPoint: UnitPoint(x: 0.5, y: botY / h)
        )
        .mask {
            Canvas(renderer: { ctx, size in
                ctx.addFilter(.alphaThreshold(min: 0.5, color: .white))
                ctx.addFilter(.blur(radius: 8))
                ctx.drawLayer { layer in
                    let mx = size.width / 2
                    if let anchor = layer.resolveSymbol(id: 0) {
                        layer.draw(anchor, at: CGPoint(x: mx, y: islandCenterY))
                    }
                    if let pill = layer.resolveSymbol(id: 1) {
                        layer.draw(pill, at: CGPoint(x: mx, y: pillCenterY))
                    }
                }
            }, symbols: {
                Capsule(style: .continuous)
                    .frame(width: anchorWidth, height: anchorHeight)
                    .tag(0)
                Capsule(style: .continuous)
                    .frame(width: pillW, height: pillH)
                    .tag(1)
            })
        }
        .shadow(color: .black.opacity(0.28), radius: 10, y: 5)
    }

    private var content: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .bold))
                .rotationEffect(.degrees(spin ? 360 : 0))
            Text("正在同步收藏")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(width: pillWidth, height: pillHeight)
        .frame(maxWidth: .infinity)
        .offset(y: pillCenterY - pillHeight / 2)
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }
}

#Preview {
    FavoriteView()
        .environment(AppFavoriteModel())
}
