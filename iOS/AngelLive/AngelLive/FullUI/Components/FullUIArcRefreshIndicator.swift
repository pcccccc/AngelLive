import SwiftUI
import UIKit
import SharedAssets

/// Place inside the actual scroll/list content so ancestry identifies only that scroller.
/// The existing `.refreshable` remains the sole owner of the refresh action and timing.
struct FullUIArcRefreshIndicator: UIViewRepresentable {
    let isEnabled: Bool
    let isRefreshing: Bool

    func makeUIView(context: Context) -> FullUIArcRefreshProbeView {
        FullUIArcRefreshProbeView()
    }

    func updateUIView(_ view: FullUIArcRefreshProbeView, context: Context) {
        view.isEnabled = isEnabled
        view.isRefreshing = isRefreshing
        view.reconcile()
    }

    static func dismantleUIView(_ view: FullUIArcRefreshProbeView, coordinator: ()) {
        view.detach()
    }
}

final class FullUIArcRefreshProbeView: UIView {
    var isEnabled = false
    var isRefreshing = false
    private let decoration = ArcRefreshControlDecoration()
    private weak var observedScrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var attachmentTask: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { detach(); return }
        reconcile()
        // SwiftUI may install refreshControl after attaching its content view.
        // Retry once after that transaction, then use real layout/scroll/update events.
        attachmentTask?.cancel()
        attachmentTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reconcile()
    }

    func reconcile() {
        guard isEnabled, window != nil else { detach(); return }
        guard let scrollView = enclosingScrollView() else { return }
        if observedScrollView !== scrollView {
            offsetObservation = nil
            decoration.detach()
            observedScrollView = scrollView
            offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reconcile() }
            }
        }
        if let control = scrollView.refreshControl {
            decoration.attach(to: control, isRefreshing: isRefreshing)
        } else {
            decoration.detach()
        }
    }

    func detach() {
        attachmentTask?.cancel()
        attachmentTask = nil
        offsetObservation = nil
        observedScrollView = nil
        decoration.detach()
    }

    private func enclosingScrollView() -> UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView { return scrollView }
            candidate = view.superview
        }
        return nil
    }
}
