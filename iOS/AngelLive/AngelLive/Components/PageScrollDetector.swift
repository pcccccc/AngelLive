//
//  PageScrollDetector.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI

/// 用于检测 TabView 滑动进度的辅助视图
struct PageScrollDetector: UIViewRepresentable {
    @Binding var currentPage: Int
    @Binding var scrollProgress: CGFloat
    let pageCount: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            // 查找父视图中的 UIScrollView
            if let scrollView = uiView.findScrollView() {
                context.coordinator.scrollView = scrollView
                scrollView.delegate = context.coordinator
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, scrollProgress: $scrollProgress, pageCount: pageCount)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        @Binding var currentPage: Int
        @Binding var scrollProgress: CGFloat
        let pageCount: Int
        weak var scrollView: UIScrollView?

        init(currentPage: Binding<Int>, scrollProgress: Binding<CGFloat>, pageCount: Int) {
            self._currentPage = currentPage
            self._scrollProgress = scrollProgress
            self.pageCount = pageCount
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let pageWidth = scrollView.frame.width
            guard pageWidth > 0 else { return }

            let offsetX = scrollView.contentOffset.x
            let progress = offsetX / pageWidth

            // 更新滚动进度
            DispatchQueue.main.async {
                self.scrollProgress = progress
            }

            // 更新当前页码
            let newPage = Int(round(progress))
            if newPage != currentPage && newPage >= 0 && newPage < pageCount {
                DispatchQueue.main.async {
                    self.currentPage = newPage
                }
            }
        }
    }
}

extension UIView {
    func findScrollView() -> UIScrollView? {
        if let scrollView = self as? UIScrollView {
            return scrollView
        }
        for subview in subviews {
            if let scrollView = subview.findScrollView() {
                return scrollView
            }
        }
        return nil
    }
}
