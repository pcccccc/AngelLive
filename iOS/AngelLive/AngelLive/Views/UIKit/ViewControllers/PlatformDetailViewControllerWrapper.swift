//
//  PlatformDetailViewControllerWrapper.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 平台详情页面包装器
/// 负责管理导航状态和命名空间，解决 PiP 模式下导航状态丢失的问题
struct PlatformDetailViewControllerWrapper: View {
    @Environment(PlatformDetailViewModel.self) var viewModel

    /// 共享导航状态 - 在 PiP 背景/前台切换时保持稳定
    @State private var navigationState = LiveRoomNavigationState()
    /// 共享命名空间 - 用于 zoom 过渡动画
    @Namespace private var roomTransitionNamespace

    var body: some View {
        baseView
            .fullScreenCover(isPresented: playerPresentedBinding) {
                playerDestination
            }
    }

    private var baseView: some View {
        PlatformDetailViewControllerRepresentable(viewModel: viewModel)
            .environment(\.liveRoomNavigationState, navigationState)
            .environment(\.roomTransitionNamespace, roomTransitionNamespace)
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
            DetailPlayerView(viewModel: RoomInfoViewModel(room: room))
                .modifier(ZoomTransitionModifier(sourceID: room.roomId, namespace: roomTransitionNamespace))
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

/// UIKit 控制器的 UIViewControllerRepresentable 包装
private struct PlatformDetailViewControllerRepresentable: UIViewControllerRepresentable {
    let viewModel: PlatformDetailViewModel

    func makeUIViewController(context: Context) -> PlatformDetailViewController {
        return PlatformDetailViewController(viewModel: viewModel)
    }

    func updateUIViewController(_ uiViewController: PlatformDetailViewController, context: Context) {
        // 根据需要更新 UI
    }
}
