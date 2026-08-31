//
//  MacOSWheelScroll.swift
//  AngelLiveCore
//
//  普通鼠标通常只产生垂直滚轮增量。横向 SwiftUI ScrollView 通过 hover 明确登记
//  当前活动区域，再把完整滚轮事件转换成 ScrollPosition 的水平位移并停止事件分发，
//  从而避免嵌套的外层纵向 ScrollView 同时滚动。
//

import SwiftUI

public extension View {
    /// 鼠标位于当前横向 ScrollView 时，把滚轮独占地转换成水平滚动。
    @ViewBuilder
    func enableMacHorizontalWheelScroll() -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            modifier(MacHorizontalWheelScrollModifier())
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// 鼠标位于当前区域时，独占滚轮并由调用方执行离散翻页。
    @ViewBuilder
    func enableMacHorizontalWheelPaging(
        _ action: @escaping @MainActor (_ delta: CGFloat) -> Void
    ) -> some View {
        #if os(macOS)
        modifier(MacHorizontalWheelPagingModifier(action: action))
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

@MainActor
@available(macOS 26.0, *)
private struct MacHorizontalWheelScrollModifier: ViewModifier {
    @State private var position = ScrollPosition(idType: Int.self, x: 0)
    @State private var requestedX: CGFloat = 0
    @State private var hoverToken = UUID()

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: position.x) { _, newValue in
                if let newValue {
                    requestedX = newValue
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    MacHorizontalWheelRouter.shared.activate(token: hoverToken) { delta, precise in
                        let currentX = position.x ?? requestedX
                        let multiplier: CGFloat = precise ? 1 : 32
                        requestedX = max(0, currentX - delta * multiplier)
                        position.scrollTo(x: requestedX)
                        return true
                    }
                case .ended:
                    MacHorizontalWheelRouter.shared.deactivate(token: hoverToken)
                }
            }
            .onDisappear {
                MacHorizontalWheelRouter.shared.deactivate(token: hoverToken)
            }
    }
}

@MainActor
private struct MacHorizontalWheelPagingModifier: ViewModifier {
    let action: @MainActor (_ delta: CGFloat) -> Void
    @State private var hoverToken = UUID()

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    MacHorizontalWheelRouter.shared.activate(token: hoverToken) { delta, _ in
                        action(delta)
                        return true
                    }
                case .ended:
                    MacHorizontalWheelRouter.shared.deactivate(token: hoverToken)
                }
            }
            .onDisappear {
                MacHorizontalWheelRouter.shared.deactivate(token: hoverToken)
            }
    }
}

@MainActor
final class MacHorizontalWheelRouter {
    typealias Handler = @MainActor (_ delta: CGFloat, _ precise: Bool) -> Bool

    static let shared = MacHorizontalWheelRouter()

    private var eventMonitor: Any?
    private var activeToken: UUID?
    private var activeHandler: Handler?

    private init() {}

    func activate(token: UUID, handler: @escaping Handler) {
        activeToken = token
        activeHandler = handler
        startMonitoringIfNeeded()
    }

    func deactivate(token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
        activeHandler = nil
    }

    func startMonitoringIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.route(event) ?? event
        }
    }

    func route(_ event: NSEvent) -> NSEvent? {
        let consumed = route(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas
        )
        return consumed ? nil : event
    }

    @discardableResult
    func route(
        deltaX horizontalDelta: CGFloat,
        deltaY verticalDelta: CGFloat,
        hasPreciseScrollingDeltas: Bool
    ) -> Bool {
        guard let activeHandler else { return false }
        let dominantDelta = abs(horizontalDelta) >= abs(verticalDelta)
            ? horizontalDelta
            : verticalDelta
        guard dominantDelta != 0 else { return false }
        return activeHandler(dominantDelta, hasPreciseScrollingDeltas)
    }
}
#endif
