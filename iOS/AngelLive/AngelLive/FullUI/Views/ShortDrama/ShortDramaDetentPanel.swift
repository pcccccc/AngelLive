import SwiftUI

enum ShortDramaPanelDetent: Equatable {
    case closed
    case medium
    case large

    func height(using metrics: ShortDramaPanelMetrics) -> CGFloat {
        switch self {
        case .closed: 0
        case .medium: metrics.mediumHeight
        case .large: metrics.largeHeight
        }
    }
}

struct ShortDramaPanelMetrics {
    let safeBottom: CGFloat
    let panelWidth: CGFloat
    let mediumHeight: CGFloat
    let largeHeight: CGFloat
    var hasDistinctDetents: Bool { largeHeight - mediumHeight >= 1 }

    init(
        containerSize: CGSize,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        isPad: Bool
    ) {
        self.safeBottom = safeBottom
        panelWidth = isPad ? min(560, containerSize.width) : containerSize.width

        // GeometryReader is in the safe-area layout; add both insets once to recover full height.
        let fullHeight = containerSize.height + safeTop + safeBottom
        largeHeight = max(0, fullHeight - safeTop - 12)
        mediumHeight = min(max(420, fullHeight * 0.52), largeHeight)
    }
}

struct ShortDramaDetentPanel<Content: View>: View {
    let isPresented: Bool
    let isInteractive: Bool
    let visibleHeight: CGFloat
    let presentationOpacity: Double
    let width: CGFloat
    let dimOpacity: Double
    let closeAccessibilityLabel: String
    let onDismiss: () -> Void
    let onToggleDetent: () -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onDragCancelled: () -> Void
    let content: Content

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 28,
            style: .continuous
        )
    }

    init(
        isPresented: Bool,
        isInteractive: Bool,
        visibleHeight: CGFloat,
        presentationOpacity: Double,
        width: CGFloat,
        dimOpacity: Double,
        closeAccessibilityLabel: String,
        onDismiss: @escaping () -> Void,
        onToggleDetent: @escaping () -> Void,
        onDragChanged: @escaping (DragGesture.Value) -> Void,
        onDragEnded: @escaping (DragGesture.Value) -> Void,
        onDragCancelled: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isPresented = isPresented
        self.isInteractive = isInteractive
        self.visibleHeight = visibleHeight
        self.presentationOpacity = presentationOpacity
        self.width = width
        self.dimOpacity = dimOpacity
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.onDismiss = onDismiss
        self.onToggleDetent = onToggleDetent
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        self.onDragCancelled = onDragCancelled
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(isPresented ? dimOpacity : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isPresented else { return }
                    onDismiss()
                }
                .allowsHitTesting(isPresented && visibleHeight > 0)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.34))
                    .frame(width: 36, height: 4)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .shortDramaPanelDragRegion(
                        onChanged: onDragChanged,
                        onEnded: onDragEnded,
                        onCancelled: onDragCancelled
                    )
                    .accessibilityHidden(true)

                content.frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: width, height: max(0, visibleHeight), alignment: .top)
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(closeAccessibilityLabel)
                .padding(.top, 20)
                .padding(.trailing, 16)
            }
            .contentShape(shape)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .clipShape(shape)
            .opacity(presentationOpacity)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(isPresented ? .isModal : [])
            .accessibilityAction(.escape) {
                guard isPresented else { return }
                onDismiss()
            }
            .accessibilityAction(named: Text("展开或收起面板")) {
                guard isPresented else { return }
                onToggleDetent()
            }
            .onKeyPress(.escape) {
                guard isPresented else { return .ignored }
                onDismiss()
                return .handled
            }
            .accessibilityHidden(!isPresented || !isInteractive)
            .allowsHitTesting(isPresented && isInteractive && visibleHeight > 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
    }
}

struct ShortDramaPanelDragRegion: ViewModifier {
    let onChanged: (DragGesture.Value) -> Void
    let onEnded: (DragGesture.Value) -> Void
    let onCancelled: () -> Void
    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .global)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged(onChanged)
                    .onEnded(onEnded)
            )
            .onChange(of: isDragging) { wasDragging, isDragging in
                guard wasDragging, !isDragging else { return }
                Task { @MainActor in
                    await Task.yield()
                    guard !self.isDragging else { return }
                    onCancelled()
                }
            }
    }
}

extension View {
    func shortDramaPanelDragRegion(
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping (DragGesture.Value) -> Void,
        onCancelled: @escaping () -> Void = {}
    ) -> some View {
        modifier(ShortDramaPanelDragRegion(onChanged: onChanged, onEnded: onEnded, onCancelled: onCancelled))
    }
}
