import SwiftUI
import UIKit

struct FullUILandscapePlayerLayout {
    static let edgeInset: CGFloat = 16
    static let progressGap: CGFloat = 8

    let insets: EdgeInsets
    let lockInset: CGFloat
    let defersSystemGestures: Bool
    let safeAreaBottom: CGFloat

    init(geometry: GeometryProxy, window: UIWindow?, direction: LayoutDirection) {
        let safe = geometry.safeAreaInsets
        let windowSafe = window?.safeAreaInsets ?? .zero
        let left = direction == .leftToRight ? safe.leading : safe.trailing
        let right = direction == .leftToRight ? safe.trailing : safe.leading
        let fullBounds = CGRect(x: -left, y: -safe.top,
                                width: geometry.size.width + left + right,
                                height: geometry.size.height + safe.top + safe.bottom)
        let isDisplayFullscreen = Self.coversDisplay(window)
        defersSystemGestures = isDisplayFullscreen
        safeAreaBottom = safe.bottom
        lockInset = max(left, windowSafe.left) + Self.edgeInset

        // SDK 27 resolves the system container shape at the full viewport bounds.
        // At zero corner offset the resolved radius is the container radius itself.
        if #available(iOS 27.0, *), isDisplayFullscreen,
           window?.traitCollection.userInterfaceIdiom == .phone,
           let corners = geometry.concentricCornerRadii(in: fullBounds) {
            let radius = min(corners.topLeading, corners.topTrailing,
                             corners.bottomLeading, corners.bottomTrailing)
            let largest = max(corners.topLeading, corners.topTrailing,
                              corners.bottomLeading, corners.bottomTrailing)
            if radius >= FullUIPlayerChrome.controlSize / 2, largest - radius < 0.5 {
                let edge = radius - FullUIPlayerChrome.controlSize / 2
                insets = EdgeInsets(top: edge, leading: edge, bottom: edge, trailing: edge)
                return
            }
        }

        let leading = direction == .leftToRight ? windowSafe.left : windowSafe.right
        let trailing = direction == .leftToRight ? windowSafe.right : windowSafe.left
        // The bottom safe area already provides clearance for the home indicator.
        insets = EdgeInsets(top: max(max(safe.top, windowSafe.top) + Self.edgeInset,
                                    FullUILandscapePlayerStatus.bottomEdge),
                            leading: max(safe.leading, leading) + Self.edgeInset,
                            bottom: max(safe.bottom, windowSafe.bottom, Self.edgeInset),
                            trailing: max(safe.trailing, trailing) + Self.edgeInset)
    }

    var bottomControlBand: CGFloat { insets.bottom + FullUIPlayerChrome.controlSize }

    private static func coversDisplay(_ window: UIWindow?) -> Bool {
        guard let window, let screen = window.windowScene?.screen else { return false }
        let display = screen.coordinateSpace.bounds
        let frame = window.convert(window.bounds, to: screen.coordinateSpace)
        return abs(frame.minX - display.minX) < 1 && abs(frame.minY - display.minY) < 1
            && abs(frame.maxX - display.maxX) < 1 && abs(frame.maxY - display.maxY) < 1
    }
}

extension EnvironmentValues {
    @Entry var fullUILandscapePlayerLayout: FullUILandscapePlayerLayout? = nil
    @Entry var fullUIPlayerShowsRoomBanner = false
}

struct FullUIPlayerStatusBar: ViewModifier {
    let isLandscapeFullscreen: Bool
    var hidesOutsideLandscape = false

    func body(content: Content) -> some View {
        let hidden = isLandscapeFullscreen || hidesOutsideLandscape
        if #available(iOS 27.0, *) {
            content.toolbarVisibility(hidden ? .hidden : .automatic, for: .statusBar)
        } else {
            content.statusBarHidden(hidden)
        }
    }
}

struct FullUILandscapePlayerLock: View {
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(FullUIPlayerChrome.symbolFont)
                .foregroundStyle(.white)
                .frame(width: FullUIPlayerChrome.controlSize, height: FullUIPlayerChrome.controlSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fullUIPlayerGlass(in: Circle())
        .fullUIPlayerShadow(in: Circle())
        .accessibilityLabel(isLocked ? "解锁" : "锁定")
    }
}
