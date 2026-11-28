import SwiftUI

/// Read-only focus stops let the remote scroll through informational content.
struct TVReadableCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 26))
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .foregroundStyle(.white)
            .background(.black.opacity(0.62), in: .rect(cornerRadius: 16))
            .modifier(TVReadingFocus(cornerRadius: 16))
    }
}

struct TVReadingFocus: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(focused ? 1 : 0.12), lineWidth: focused ? 3 : 1)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .combine)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
    }
}
