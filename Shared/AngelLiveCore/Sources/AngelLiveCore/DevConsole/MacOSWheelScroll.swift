//
//  MacOSWheelScroll.swift
//  AngelLiveCore
//
//  macOS SwiftUI 横向滚动视图的系统滚动条适配。
//

import SwiftUI

public extension View {
    /// 强制隐藏所在 SwiftUI ScrollView 底层的 AppKit 横向 scroller。
    /// 应加在 ScrollView 的内容视图上，以便命中最近的 NSScrollView。
    @ViewBuilder
    func hideMacHorizontalScrollIndicator() -> some View {
        #if os(macOS)
        self.background(MacHorizontalScrollIndicatorHider())
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct MacHorizontalScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> MacHorizontalScrollIndicatorHiderView {
        MacHorizontalScrollIndicatorHiderView()
    }

    func updateNSView(_ nsView: MacHorizontalScrollIndicatorHiderView, context: Context) {
        nsView.hideHorizontalScroller()
    }
}

private final class MacHorizontalScrollIndicatorHiderView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideHorizontalScroller()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        hideHorizontalScroller()
    }

    override func layout() {
        super.layout()
        configureEnclosingScrollView()
    }

    func hideHorizontalScroller() {
        DispatchQueue.main.async { [weak self] in
            self?.configureEnclosingScrollView()
        }
    }

    private func configureEnclosingScrollView() {
        guard let scrollView = enclosingScrollView else { return }
        if scrollView.hasHorizontalScroller {
            scrollView.hasHorizontalScroller = false
        }
        if scrollView.horizontalScroller?.isHidden == false {
            scrollView.horizontalScroller?.isHidden = true
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
    }
}

#endif
