import SwiftUI
import UIKit

/// FullUI's navigation-edge policy, shared by SwiftUI and UIKit screens.
@MainActor
enum FullUINavigationStyle {
    static func configure(_ scrollView: UIScrollView) {
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .soft
        }
    }
}

extension View {
    @ViewBuilder
    func fullUINavigationStyle(enabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(enabled ? .soft : nil, for: .top)
        } else {
            self
        }
    }
}
