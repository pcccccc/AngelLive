//
//  PlayerGestureView.swift
//  AngelLive
//
//  播放器手势处理视图
//  - 单击显示/隐藏控制层
//  - 双击全屏/退出全屏
//  - 左半边上下滑动调节亮度
//  - 右半边上下滑动调节音量
//

import SwiftUI
import MediaPlayer
import KSPlayer
import AngelLiveCore
internal import AVFoundation

/// 手势调节类型
enum GestureAdjustType {
    case none
    case brightness
    case volume
}

/// 播放器手势处理视图
struct PlayerGestureView: View {
    @Environment(\.isIPadFullscreen) private var isIPadFullscreen: Binding<Bool>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// 单击回调
    var onSingleTap: (() -> Void)?
    /// 锁定状态绑定
    @Binding var isLocked: Bool

    /// 当前调节类型
    @State private var adjustType: GestureAdjustType = .none
    /// 当前调节值 (0.0 - 1.0)
    @State private var adjustValue: CGFloat = 0.0
    /// 是否显示调节指示器
    @State private var showIndicator: Bool = false
    /// 滑动起始位置的值
    @State private var startValue: CGFloat = 0.0
    /// 是否正在滑动
    @State private var isDragging: Bool = false

    /// 音量滑块（系统音量控制）
    private let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.isHidden = false
        view.alpha = 0.01
        return view
    }()

    /// 检测是否为横屏
    private var isLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact ||
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    var body: some View {
        GeometryReader { geometry in
            let bottomSafeArea: CGFloat = 50 // 底部安全区域高度，避免与系统手势冲突

            ZStack {
                // 透明手势接收层（底部留出安全区域）
                Color.clear
                    // 从后台返回时重置手势状态（修复 PIP 返回后 HUD 显示问题）
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        resetGestureState()
                    }
                    .contentShape(Rectangle())
                    .padding(.bottom, bottomSafeArea)
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                // 锁定时或禁用滑动手势时不响应
                                guard !isLocked && GeneralSettingModel().enablePlayerGesture else { return }
                                // 检查起始位置是否在底部安全区域内
                                guard value.startLocation.y < geometry.size.height - bottomSafeArea else { return }
                                handleDragChanged(value: value, in: geometry.size)
                            }
                            .onEnded { _ in
                                handleDragEnded()
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                // 锁定时禁用双击手势
                                guard !isLocked else { return }
                                handleDoubleTap()
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 1)
                            .onEnded {
                                // 只有在没有拖动的情况下才响应单击
                                if !isDragging {
                                    // 延迟执行单击，给双击判断留时间
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        onSingleTap?()
                                    }
                                }
                            }
                    )

                // 调节指示器
                if showIndicator {
                    adjustIndicator
                        .transition(.opacity)
                }

                // 隐藏的音量控制视图
                VolumeViewWrapper(volumeView: volumeView)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // 进入后台/画中画时重置手势状态
            resetGestureState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // 返回前台时重置手势状态
            resetGestureState()
        }
    }

    /// 重置手势状态
    private func resetGestureState() {
        showIndicator = false
        adjustType = .none
        isDragging = false
    }

    // MARK: - 调节指示器

    private var adjustIndicator: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: adjustType == .brightness ? "sun.max.fill" : "speaker.wave.2.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .frame(width: 24)

            // 进度条（水平方向）
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.3))

                    // 进度
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white)
                        .frame(width: geo.size.width * adjustValue)
                }
            }
            .frame(width: 120, height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 手势处理

    /// 处理双击手势
    private func handleDoubleTap() {
        if AppConstants.Device.isIPad {
            // iPad: 切换全屏模式
            withAnimation(.easeInOut(duration: 0.3)) {
                isIPadFullscreen.wrappedValue.toggle()
            }
        } else {
            // iPhone: 切换横屏/竖屏
            toggleiPhoneOrientation()
        }
    }

    /// 切换 iPhone 屏幕方向
    private func toggleiPhoneOrientation() {
        let isCurrentlyLandscape = UIApplication.isLandscape
        let targetOrientation: UIInterfaceOrientationMask = isCurrentlyLandscape ? .portrait : .landscape

        KSOptions.supportedInterfaceOrientations = targetOrientation

        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first else { return }

            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: targetOrientation
            )

            windowScene.requestGeometryUpdate(geometryPreferences) { error in
                print("❌ 切换屏幕方向失败: \(error)")
            }

            if let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                rootVC.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            let orientation: UIInterfaceOrientation = isCurrentlyLandscape ? .portrait : .landscapeRight
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    /// 处理拖动手势变化
    private func handleDragChanged(value: DragGesture.Value, in size: CGSize) {
        let startX = value.startLocation.x
        let translation = value.translation

        // 判断是否为垂直滑动（垂直位移大于水平位移）
        guard abs(translation.height) > abs(translation.width) else { return }

        isDragging = true

        // 确定调节类型
        if adjustType == .none {
            if startX < size.width / 2 {
                // 左半边 - 亮度
                adjustType = .brightness
                startValue = UIScreen.main.brightness
            } else {
                // 右半边 - 音量
                adjustType = .volume
                startValue = getSystemVolume()
            }
            adjustValue = startValue
            withAnimation(.easeInOut(duration: 0.2)) {
                showIndicator = true
            }
        }

        // 计算调节值（向上滑动增加，向下滑动减少）
        let sensitivity: CGFloat = 1.0 / size.height // 整个高度对应 0-1
        let delta = -translation.height * sensitivity
        let newValue = max(0, min(1, startValue + delta))
        adjustValue = newValue

        // 应用调节
        switch adjustType {
        case .brightness:
            UIScreen.main.brightness = newValue
        case .volume:
            setSystemVolume(newValue)
        case .none:
            break
        }
    }

    /// 处理拖动手势结束
    private func handleDragEnded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showIndicator = false
        }
        // 延迟重置状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            adjustType = .none
            isDragging = false
        }
    }

    // MARK: - 音量控制

    /// 获取系统音量
    private func getSystemVolume() -> CGFloat {
        let audioSession = AVAudioSession.sharedInstance()
        return CGFloat(audioSession.outputVolume)
    }

    /// 设置系统音量
    private func setSystemVolume(_ volume: CGFloat) {
        // 使用 MPVolumeView 的 slider 来设置音量
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            DispatchQueue.main.async {
                slider.value = Float(volume)
            }
        }
    }
}

// MARK: - MPVolumeView Wrapper

struct VolumeViewWrapper: UIViewRepresentable {
    let volumeView: MPVolumeView

    func makeUIView(context: Context) -> MPVolumeView {
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
