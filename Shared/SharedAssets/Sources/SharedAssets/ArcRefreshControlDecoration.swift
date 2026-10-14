#if os(iOS)
import SwiftUI
import UIKit

/// Opt-in visual decoration for an existing refresh control. It does not own refreshing,
/// targets, actions, scroll insets, or the control's accessibility semantics.
@available(iOS 16.0, *)
@MainActor
public final class ArcRefreshControlDecoration {
    private weak var refreshControl: UIRefreshControl?
    private var originalTint: UIColor?
    private let state = ArcRefreshIndicatorState()
    private var indicator: (UIView & UIContentView)?
    private var constraints: [NSLayoutConstraint] = []

    public init() {}

    public func attach(to control: UIRefreshControl, isRefreshing: Bool = false) {
        if refreshControl !== control {
            detach()
            refreshControl = control
            originalTint = control.tintColor
            state.tint = Color(uiColor: control.tintColor ?? .secondaryLabel)
            control.tintColor = .clear

            let content: UIView & UIContentView
            if let indicator {
                content = indicator
            } else {
                content = UIHostingConfiguration {
                    ArcRefreshIndicator(state: state)
                }
                .margins(.all, 0)
                .makeContentView()
                content.backgroundColor = .clear
                content.isUserInteractionEnabled = false
                content.accessibilityElementsHidden = true
                content.translatesAutoresizingMaskIntoConstraints = false
                indicator = content
            }
            control.addSubview(content)
            constraints = [
                content.centerXAnchor.constraint(equalTo: control.centerXAnchor),
                content.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                content.widthAnchor.constraint(equalToConstant: 20),
                content.heightAnchor.constraint(equalToConstant: 20)
            ]
            NSLayoutConstraint.activate(constraints)
        }
        update(isRefreshing: isRefreshing || control.isRefreshing)
    }

    public func update(isRefreshing: Bool) {
        guard state.isRefreshing != isRefreshing else { return }
        state.isRefreshing = isRefreshing
    }

    public func detach() {
        if let refreshControl { refreshControl.tintColor = originalTint }
        NSLayoutConstraint.deactivate(constraints)
        constraints = []
        indicator?.removeFromSuperview()
        refreshControl = nil
        originalTint = nil
        update(isRefreshing: false)
    }
}

@available(iOS 16.0, *)
@MainActor
private final class ArcRefreshIndicatorState: ObservableObject {
    @Published var isRefreshing = false
    @Published var tint = Color.secondary
}

@available(iOS 16.0, *)
private struct ArcRefreshIndicator: View {
    @ObservedObject var state: ArcRefreshIndicatorState
    var body: some View {
        // Before refresh begins, the pull reveals the same stationary arc.
        ArcSpinner(size: 20, lineWidth: 1.5, isAnimating: state.isRefreshing)
            .tint(state.tint)
            .accessibilityHidden(true)
    }
}
#endif
