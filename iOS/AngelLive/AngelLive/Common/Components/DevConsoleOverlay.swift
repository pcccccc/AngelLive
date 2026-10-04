//
//  DevConsoleOverlay.swift
//  AngelLive
//
//  Created by pangchong on 2026/4/2.
//
//  iOS 这层只负责"宿主壳":独立 UIWindow + 可拖拽浮动球 + 底部 sheet 容器。
//  控制台内容(header/搜索/筛选/列表/详情)统一走 AngelLiveCore.PluginConsoleView 复用。
//

import SwiftUI
import AngelLiveCore

// MARK: - 管理器：直接添加到 keyWindow 上
// 注:整段代码常驻所有构建,运行时是否真的弹窗由 GeneralSettingModel.globalDeveloperMode 控制,
// 用户不开"开发者模式"就不会创建 overlayWindow,App Store 构建也只是多了未激活的代码。

@MainActor
final class DevConsoleWindowManager {

    static let shared = DevConsoleWindowManager()

    private var overlayWindow: DevConsolePassthroughWindow?
    private var presentsFullUI = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncVisibility() }
        }
    }

    func setup(presentsFullUI: Bool) {
        let modeChanged = self.presentsFullUI != presentsFullUI
        self.presentsFullUI = presentsFullUI
        if modeChanged, overlayWindow != nil {
            hide()
        }
        syncVisibility()
    }

    private func syncVisibility() {
        let enabled = UserDefaults.shared.bool(forKey: GeneralSettingModel.globalDeveloperMode)
        if enabled {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        guard overlayWindow == nil else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let window = DevConsolePassthroughWindow(windowScene: scene)
        window.windowLevel = .alert + 100
        window.backgroundColor = .clear
        window.isHidden = false

        let container = DevConsoleContainerView(frame: window.bounds, presentsFullUI: presentsFullUI)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let rootVC = DevConsolePassthroughViewController()
        rootVC.view.addSubview(container)
        window.rootViewController = rootVC

        overlayWindow = window
    }

    private func hide() {
        guard let window = overlayWindow else { return }
        if let container = window.rootViewController?.view.subviews.first as? DevConsoleContainerView {
            container.dismissPanel()
        }
        window.isHidden = true
        window.rootViewController = nil
        overlayWindow = nil
    }
}

// MARK: - 透传触摸的 Window 和 ViewController

/// 独立窗口：不在触摸区域内的事件透传到下层窗口
private class DevConsolePassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // 如果命中的是 rootVC 的 view 本身，说明没有子视图响应，透传
        return hit === rootViewController?.view ? nil : hit
    }
}

/// 根控制器：透明背景，不影响状态栏
private class DevConsolePassthroughViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    // 不影响下层的状态栏样式
    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
}

// MARK: - 容器视图（透传触摸 + 管理按钮和面板）

private class DevConsoleContainerView: UIView {

    private let floatingButton = UIButton(type: .custom)
    private var buttonCenter: CGPoint = .zero
    private var isPanelOpen = false

    private var dimmingView: UIView?
    private var panelHosting: UIHostingController<AnyView>?

    // iOS 26 Liquid Glass 效果层
    private var glassBackgroundView: UIView?
    private let presentsFullUI: Bool

    init(frame: CGRect, presentsFullUI: Bool) {
        self.presentsFullUI = presentsFullUI
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        setupFloatingButton()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if buttonCenter == .zero {
            buttonCenter = CGPoint(
                x: 28 + 4,
                y: bounds.height - safeAreaInsets.bottom - 80
            )
            floatingButton.center = buttonCenter
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 {
            let converted = subview.convert(point, from: self)
            if let hit = subview.hitTest(converted, with: event) {
                return hit
            }
        }
        return nil
    }

    // MARK: - 浮动按钮

    private func setupFloatingButton() {
        let size: CGFloat = 52
        floatingButton.frame = CGRect(x: 0, y: 0, width: size, height: size)
        floatingButton.clipsToBounds = false

        if #available(iOS 26.0, *) {
            // iOS 26: 使用系统风格，让 Liquid Glass 自动生效
            floatingButton.configuration = {
                var config = UIButton.Configuration.plain()
                config.image = UIImage(
                    systemName: "ladybug.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
                )
                config.baseForegroundColor = .white
                config.background.backgroundColor = .systemRed
                config.cornerStyle = .capsule
                return config
            }()
            floatingButton.layer.cornerRadius = size / 2
            // 阴影
            floatingButton.layer.shadowColor = UIColor.black.cgColor
            floatingButton.layer.shadowOpacity = 0.25
            floatingButton.layer.shadowOffset = CGSize(width: 0, height: 3)
            floatingButton.layer.shadowRadius = 10
        } else {
            // iOS 17-25: 手动渐变 + 阴影
            floatingButton.layer.cornerRadius = size / 2

            let gradient = CAGradientLayer()
            gradient.frame = CGRect(x: 0, y: 0, width: size, height: size)
            gradient.cornerRadius = size / 2
            gradient.colors = [
                UIColor.systemRed.cgColor,
                UIColor.systemRed.withAlphaComponent(0.8).cgColor
            ]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            floatingButton.layer.insertSublayer(gradient, at: 0)

            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            floatingButton.setImage(UIImage(systemName: "ladybug.fill", withConfiguration: config), for: .normal)
            floatingButton.tintColor = .white

            floatingButton.layer.shadowColor = UIColor.black.cgColor
            floatingButton.layer.shadowOpacity = 0.3
            floatingButton.layer.shadowOffset = CGSize(width: 0, height: 4)
            floatingButton.layer.shadowRadius = 8
        }

        floatingButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        floatingButton.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))

        addSubview(floatingButton)
    }

    // MARK: - 按钮交互

    @objc private func buttonTapped() {
        isPanelOpen ? dismissPanel() : showPanel()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began:
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                self.floatingButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            }
        case .changed:
            floatingButton.center = CGPoint(
                x: buttonCenter.x + translation.x,
                y: buttonCenter.y + translation.y
            )
        case .ended, .cancelled:
            let raw = CGPoint(
                x: buttonCenter.x + translation.x,
                y: buttonCenter.y + translation.y
            )
            let snapped = snapToEdge(raw)
            buttonCenter = snapped
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.8) {
                self.floatingButton.center = snapped
                self.floatingButton.transform = .identity
            }
        default: break
        }
    }

    private func snapToEdge(_ center: CGPoint) -> CGPoint {
        let half: CGFloat = 28
        let pad: CGFloat = 4
        let minX = half + pad
        let maxX = bounds.width - half - pad
        let minY = safeAreaInsets.top + half + pad
        let maxY = bounds.height - safeAreaInsets.bottom - half - pad

        return CGPoint(
            x: center.x < bounds.width / 2 ? minX : maxX,
            y: min(max(center.y, minY), maxY)
        )
    }

    // MARK: - 面板

    func showPanel() {
        guard !isPanelOpen else { return }
        isPanelOpen = true

        UIView.animate(withDuration: 0.2) {
            self.floatingButton.alpha = 0
            self.floatingButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }

        // 遮罩
        let dimming = UIView(frame: bounds)
        dimming.backgroundColor = .black.withAlphaComponent(0.35)
        dimming.alpha = 0
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleDismiss)))
        insertSubview(dimming, belowSubview: floatingButton)
        self.dimmingView = dimming

        // SwiftUI 面板 —— 内容跨端复用 AngelLiveCore.PluginConsoleView,
        // iOS 这一层只贴底部 sheet 外观(把手 + ultraThinMaterial 玻璃 + 拖拽下滑关闭)。
        let panel = ConsolePanel(
            presentsFullUI: presentsFullUI,
            onDismiss: { [weak self] in self?.dismissPanel() }
        )
        let hosting = UIHostingController(rootView: AnyView(panel))
        hosting.view.backgroundColor = .clear

        let parentVC = findViewController()
        parentVC?.addChild(hosting)
        addSubview(hosting.view)
        hosting.didMove(toParent: parentVC)

        let panelHeight = bounds.height * 0.5
        hosting.view.frame = CGRect(
            x: 6, y: bounds.height,
            width: bounds.width - 12, height: panelHeight
        )
        self.panelHosting = hosting

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5) {
            dimming.alpha = 1
            hosting.view.frame.origin.y = self.bounds.height - panelHeight - self.safeAreaInsets.bottom
        }
    }

    @objc private func handleDismiss() {
        dismissPanel()
    }

    func dismissPanel() {
        guard isPanelOpen else { return }
        isPanelOpen = false

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.dimmingView?.alpha = 0
            self.panelHosting?.view.frame.origin.y = self.bounds.height
        } completion: { _ in
            self.dimmingView?.removeFromSuperview()
            self.dimmingView = nil
            self.panelHosting?.willMove(toParent: nil)
            self.panelHosting?.view.removeFromSuperview()
            self.panelHosting?.removeFromParent()
            self.panelHosting = nil
        }

        UIView.animate(withDuration: 0.35, delay: 0.1, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.8) {
            self.floatingButton.alpha = 1
            self.floatingButton.transform = .identity
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}

// MARK: - 底部 sheet 外观包装

/// iOS 专有的底部 sheet 外观:顶部把手(可下滑关闭) + ultraThinMaterial 玻璃背景。
/// 内容部分直接复用 AngelLiveCore 里的 `PluginConsoleView`。
private struct ConsolePanel: View {
    let presentsFullUI: Bool
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            panelHandle
            if presentsFullUI {
                DeveloperConsoleView(onClose: onDismiss)
            } else {
                PluginConsoleView(onClose: onDismiss)
            }
        }
        .modifier(PanelBackgroundModifier())
        .offset(y: max(0, dragOffset))
    }

    private var panelHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(.secondary.opacity(0.5))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        if value.translation.height > 100 || value.predictedEndTranslation.height > 200 {
                            onDismiss()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
            )
    }
}

/// iOS 26 用 glassEffect,低版本用 ultraThinMaterial。
private struct PanelBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 24, y: -6)
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
        }
    }
}

// MARK: - SwiftUI 入口

struct DevConsoleOverlay: View {
    @Environment(PluginAvailabilityService.self) private var pluginAvailability

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DevConsoleWindowManager.shared.setup(
                    presentsFullUI: pluginAvailability.hasAvailablePlugins
                )
            }
            .onChange(of: pluginAvailability.hasAvailablePlugins) { _, presentsFullUI in
                DevConsoleWindowManager.shared.setup(presentsFullUI: presentsFullUI)
            }
    }
}
