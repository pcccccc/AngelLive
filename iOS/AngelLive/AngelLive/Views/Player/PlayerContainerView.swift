//
//  PlayerContainerView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AVKit
import AngelLiveCore
import AngelLiveDependencies
import Kingfisher
import KSPlayer
#if canImport(UIKit)
import UIKit
#endif

struct PlayerContainerView: View {
    @Binding var isFullScreen: Bool

    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @StateObject private var coordinator = KSVideoPlayer.Coordinator()
    @State private var controlsVisible = true
    @State private var showingDanmuSettings = false

    private var isIPadLandscape: Bool {
        AppConstants.Device.isIPad &&
        horizontalSizeClass == .regular &&
        verticalSizeClass == .compact
    }

    @Environment(\.safeAreaInsets) private var safeAreaInsets

    var body: some View {
        Group {
            if isFullScreen {
                GeometryReader { proxy in
                    let size = proxy.safeSize
                    playerSurface(size: size)
                        .frame(width: size.width, height: size.height)
                        .ignoresSafeArea()
                }
            } else if isIPadLandscape {
                GeometryReader { proxy in
                    let size = proxy.safeSize
                    playerSurface(size: size)
                        .frame(width: size.width, height: size.height)
                }
            } else {
                VStack(spacing: 0) {
                    if safeAreaInsets.top > 0 {
                        Color.clear.frame(height: safeAreaInsets.top)
                    }

                    GeometryReader { proxy in
                        let size = proxy.safeSize
                        playerSurface(size: size)
                            .frame(width: size.width, height: size.height)
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.black)
        .onAppear(perform: setupCoordinator)
        .sheet(isPresented: $showingDanmuSettings) {
            NavigationStack {
                DanmuSettingViewiOS()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func playerSurface(size: CGSize) -> some View {
        if isFullScreen {
            basePlayerSurface(size: size)
                .ignoresSafeArea()
        } else {
            basePlayerSurface(size: size)
        }
    }

    private func basePlayerSurface(size: CGSize) -> some View {
        ZStack {
            Color.black
            mediaContent(size: size)
            if controlsVisible {
                overlay(size: size)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .center)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible.toggle()
            }
        }
    }

    @ViewBuilder
    private func mediaContent(size: CGSize) -> some View {
        if let url = viewModel.currentPlayURL {
            KSVideoPlayer(
                coordinator: ObservedObject(wrappedValue: coordinator),
                url: url,
                options: viewModel.playerOption
            )
            .frame(width: size.width, height: size.height)
            .modifier(FullScreenVideoModifier(isFullScreen: isFullScreen))
        } else if viewModel.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                Text("正在解析直播地址...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: size.width, height: size.height)
        } else {
            KFImage(URL(string: viewModel.currentRoom.roomCover))
                .placeholder {
                    Rectangle()
                        .fill(AppConstants.Colors.placeholderGradient())
                }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        }
    }

    private func overlay(size: CGSize) -> some View {
        ZStack {
            if isFullScreen {
                fullScreenOverlay(size: size)
            } else {
                embeddedOverlay
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(true)
    }

    private var embeddedOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .overlay(alignment: .bottom) {
                HStack(spacing: 16) {
                    HStack(spacing: 16) {
                        controlButton(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill", action: togglePlayPause)
                        controlButton(systemName: "arrow.clockwise", action: refreshStream)
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        controlButton(systemName: "pip", action: togglePictureInPicture)
                        controlButton(systemName: "arrow.up.left.and.arrow.down.right", action: enterFullScreen)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func fullScreenOverlay(size: CGSize) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: min(size.height * 0.35, 220))
            .overlay(alignment: .top) {
                HStack(spacing: 12) {
                    controlButton(systemName: "chevron.left", action: exitFullScreen)

                    KFImage(URL(string: viewModel.currentRoom.userHeadImg))
                        .placeholder {
                            Circle().fill(Color.white.opacity(0.2))
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentRoom.userName)
                            .font(.headline)
                        Text("人气 \(viewModel.currentRoom.liveWatchedCount ?? "--")")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        controlButton(systemName: contentModeIcon, isHighlighted: coordinator.isScaleAspectFill, action: toggleContentMode)
                        AirPlayRoutePicker()
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 44)
            }

            Spacer()

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: min(size.height * 0.35, 220))
            .overlay(alignment: .bottom) {
                HStack(spacing: 16) {
                    HStack(spacing: 16) {
                        controlButton(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill", action: togglePlayPause)
                        controlButton(systemName: "arrow.clockwise", action: refreshStream)
                    }

                    Spacer()

                    HStack(spacing: 16) {
                        controlButton(systemName: viewModel.showDanmu ? "text.bubble.fill" : "text.bubble", isHighlighted: viewModel.showDanmu, action: toggleDanmu)
                        controlButton(systemName: "slider.horizontal.3") {
                            showingDanmuSettings = true
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea()
    }

    private func controlButton(systemName: String, isHighlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isHighlighted ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.45))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func setupCoordinator() {
        viewModel.setPlayerDelegate(playerCoordinator: coordinator)
        coordinator.onStateChanged = { _, state in
            viewModel.isPlaying = state.isPlaying
        }
        coordinator.onPlay = { _, _ in
            viewModel.isPlaying = true
        }
        coordinator.onFinish = { _, _ in
            viewModel.isPlaying = false
        }
        coordinator.mask(show: false, autoHide: false)
    }

    private func togglePlayPause() {
        guard let layer = coordinator.playerLayer else { return }
        if layer.state.isPlaying {
            layer.pause()
            viewModel.isPlaying = false
        } else {
            layer.play()
            viewModel.isPlaying = true
        }
    }

    private func refreshStream() {
        viewModel.refreshPlayback()
    }

    private func toggleDanmu() {
        viewModel.toggleDanmuDisplay()
    }

    private func togglePictureInPicture() {
        guard let layer = coordinator.playerLayer as? KSComplexPlayerLayer else { return }
        if layer.isPictureInPictureActive {
            layer.pipStop(restoreUserInterface: true)
        } else {
            layer.pipStart()
        }
    }

    private func toggleContentMode() {
        coordinator.isScaleAspectFill.toggle()
    }

    private var contentModeIcon: String {
        coordinator.isScaleAspectFill ? "rectangle.arrowtriangle.2.inward" : "rectangle.arrowtriangle.2.outward"
    }

    private func enterFullScreen() {
        guard !isFullScreen else { return }
        controlsVisible = true
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullScreen = true
        }
        coordinator.isScaleAspectFill = true
        if AppConstants.Device.isIPhone {
            applyLandscapeOrientation()
        }
    }

    private func exitFullScreen() {
        guard isFullScreen else { return }
        controlsVisible = true
        withAnimation(.easeInOut(duration: 0.25)) {
            isFullScreen = false
        }
        coordinator.isScaleAspectFill = false
        if AppConstants.Device.isIPhone {
            restoreDefaultOrientation()
        }
    }

    private func applyLandscapeOrientation() {
        #if canImport(UIKit)
        requestOrientation(mask: .landscape, fallback: .landscapeRight)
        #endif
    }

    private func restoreDefaultOrientation() {
        #if canImport(UIKit)
        requestOrientation(mask: .portrait, fallback: .portrait)
        #endif
    }

    #if canImport(UIKit)
    private func requestOrientation(mask: UIInterfaceOrientationMask, fallback: UIInterfaceOrientation) {
        DispatchQueue.main.async {
            KSOptions.supportedInterfaceOrientations = mask == .portrait ? nil : mask
            if #available(iOS 16.0, *) {
                if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                    let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
                    do {
                        try scene.requestGeometryUpdate(preferences)
                        UIViewController.attemptRotationToDeviceOrientation()
                        return
                    } catch {}
                }
            }
            UIDevice.current.setValue(fallback.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
    #endif
}

private struct FullScreenVideoModifier: ViewModifier {
    let isFullScreen: Bool

    func body(content: Content) -> some View {
        if isFullScreen {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}

private extension GeometryProxy {
    var safeSize: CGSize {
        CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }
}

#if canImport(UIKit)
private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .white
        picker.prioritizesVideoDevices = true
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
private struct AirPlayRoutePicker: View {
    var body: some View {
        Image(systemName: "airplayvideo")
            .font(.system(size: 18, weight: .semibold))
    }
}
#endif
