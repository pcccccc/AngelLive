import SwiftUI
import AngelLiveCore

/// Controls can disappear, move or become inaccessible while a sheet is on screen.
/// The room page owns the system presenter and the lifetime of each presentation.
@MainActor @Observable
private final class RoomPlayerSheets {
    struct Request: Identifiable {
        let id: UUID
        let initialDetent: PresentationDetent
        let detentSelection: Binding<PresentationDetent>?
        let content: () -> AnyView
        let didDismiss: () -> Void
    }

    var presented: Request?
    private var dismissing: Request?
    private var next: Request?

    var roomHeight: CGFloat = 0
    var sheetHeight: CGFloat = 0

    var coversRoom: Bool { presented != nil || dismissing != nil }

    func present(_ request: Request) {
        if coversRoom {
            let superseded = next
            next = request
            superseded?.didDismiss()
            if let presented { dismiss(presented.id) }
        } else {
            presented = request
        }
    }

    func dismiss(_ id: UUID) {
        if next?.id == id { next = nil }
        guard let presented, presented.id == id else { return }
        dismissing = presented
        self.presented = nil
    }

    func didDismiss() {
        let finished = dismissing ?? presented
        presented = nil
        dismissing = nil
        sheetHeight = 0
        finished?.didDismiss()
        if let next {
            self.next = nil
            presented = next
        }
    }
}

private extension EnvironmentValues {
    @Entry var roomPlayerSheets: RoomPlayerSheets?
}

struct RoomPlayerSheetHost: ViewModifier {
    let viewModel: RoomInfoViewModel
    @State private var sheets = RoomPlayerSheets()

    func body(content: Content) -> some View {
        content
            .environment(\.roomPlayerSheets, sheets)
            .coordinateSpace(name: "RoomPlayerPresenter")
            .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: {
                sheets.roomHeight = $0
            }
            .accessibilityHidden(sheets.coversRoom)
            .sheet(item: Binding(get: { sheets.presented }, set: { value in
                if value == nil, let current = sheets.presented { sheets.dismiss(current.id) }
            }), onDismiss: sheets.didDismiss) { request in
                request.content()
                    .roomPlayerSheetAppearance()
                    .playerSheetDetents(initial: request.initialDetent, selection: request.detentSelection)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom
                    } action: { sheets.sheetHeight = $0 }
                    .environment(viewModel)
                    .accessibilityHidden(false)
                    .accessibilityAddTraits(.isModal)
            }
    }
}

private struct RoomPlayerSheetSource<Trigger: View, Item: Identifiable, Destination: View, Standalone: View>: View {
    let trigger: Trigger
    var initialDetent: PresentationDetent = .large
    var detentSelection: Binding<PresentationDetent>?
    @Binding var item: Item?
    let onDismiss: () -> Void
    @ViewBuilder let destination: (Item) -> Destination
    @ViewBuilder let standalone: () -> Standalone
    @Environment(\.roomPlayerSheets) private var sheets
    @State private var requestID: UUID?

    var body: some View {
        if let sheets {
            trigger.onChange(of: item?.id, initial: true) {
                guard let item else {
                    if let requestID { sheets.dismiss(requestID) }
                    return
                }
                let id = UUID()
                requestID = id
                sheets.present(.init(id: id, initialDetent: initialDetent, detentSelection: detentSelection, content: { [destination] in AnyView(destination(item)) }, didDismiss: {
                    [issued = $requestID, selection = $item, onDismiss] in
                    guard issued.wrappedValue == id else { return }
                    issued.wrappedValue = nil
                    if selection.wrappedValue?.id == item.id { selection.wrappedValue = nil }
                    onDismiss()
                }))
            }
        } else {
            standalone()
        }
    }
}

private enum PlayerSheetVisibility: Hashable, Identifiable {
    case presented
    var id: Self { self }
}

/// On a bottom-attached phone sheet, keep complete room headers above the
/// sheet and keep partially covered labels out of its curved corners.
struct RoomHeaderSheetVisibility: ViewModifier {
    @Environment(\.roomPlayerSheets) private var sheets
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.verticalSizeClass) private var heightClass
    @State private var bottom: CGFloat = 0

    private var isCovered: Bool {
        guard widthClass == .compact, heightClass == .regular,
              let sheets, sheets.coversRoom, sheets.sheetHeight > 0 else { return false }
        return bottom > sheets.roomHeight - sheets.sheetHeight
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("RoomPlayerPresenter")).maxY } action: {
                bottom = $0
            }
            .opacity(isCovered ? 0 : 1)
    }
}

private extension View {
    func roomPlayerSheetAppearance() -> some View {
        playerSheetSurface()
            .tint(AppConstants.Colors.accent)
            .environment(\.usesFullUIPlayerSheets, true)
            .preferredColorScheme(.dark)
    }
}

extension View {
    func roomPlayerSheet<Item: Identifiable, Destination: View>(
        item: Binding<Item?>, onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> Destination
    ) -> some View {
        RoomPlayerSheetSource(trigger: self, item: item, onDismiss: onDismiss, destination: content) {
            self.sheet(item: item, onDismiss: onDismiss) { item in
                content(item).roomPlayerSheetAppearance().playerSheetDetents(initial: .large)
            }
        }
    }

    func roomPlayerSheet<Destination: View>(
        isPresented: Binding<Bool>, initialDetent: PresentationDetent = .large,
        selection: Binding<PresentationDetent>? = nil, onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Destination
    ) -> some View {
        let item = Binding<PlayerSheetVisibility?>(
            get: { isPresented.wrappedValue ? .presented : nil },
            set: { isPresented.wrappedValue = $0 != nil }
        )
        return RoomPlayerSheetSource(trigger: self, initialDetent: initialDetent, detentSelection: selection,
                                     item: item, onDismiss: onDismiss, destination: { _ in content() }) {
            self.sheet(isPresented: isPresented, onDismiss: onDismiss) {
                content().roomPlayerSheetAppearance()
                    .playerSheetDetents(initial: initialDetent, selection: selection)
            }
        }
    }
}
