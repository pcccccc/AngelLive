//
//  WelcomePageView.swift
//  AngelLive
//
//  Created by pangchong on 11/7/25.
//

import SwiftUI

struct WelcomeCard: Identifiable {
    var id: String = UUID().uuidString
    var symbol: String
    var title: String
    var subTitle: String
}

@resultBuilder
struct WelcomeCardResultBuilder {
    static func buildBlock(_ components: WelcomeCard...) -> [WelcomeCard] {
        components.compactMap({ $0 })
    }
}

struct WelcomePageView<Icon: View, Footer: View>: View {

    let tint: Color
    let title: String
    let icon: Icon
    let cards: [WelcomeCard]
    let footer: Footer
    let onContinue: () -> Void
    let usesResizableLayout: Bool

    @State private var animateIcon: Bool = false
    @State private var animateTitle: Bool = false
    @State private var animateCards: [Bool]
    @State private var animateFooter: Bool = false

    init(
        tint: Color,
        title: String,
        usesResizableLayout: Bool = false,
        @ViewBuilder icon: @escaping () -> Icon,
        @WelcomeCardResultBuilder cards: @escaping () -> [WelcomeCard],
        @ViewBuilder footer: @escaping () -> Footer,
        onContinue: @escaping () -> Void
    ) {
        self.tint = tint
        self.title = title
        self.usesResizableLayout = usesResizableLayout
        self.icon = icon()
        self.cards = cards()
        self.footer = footer()
        self.onContinue = onContinue
        self._animateCards = .init(initialValue: Array(repeating: false, count: self.cards.count))
    }

    var body: some View {
        VStack(spacing: 16) {
            scrollContent

            actionFooter
        }
        .interactiveDismissDisabled()
        .task { await runAnimations() }
        .setUpOnBoarding(usesResizableLayout: usesResizableLayout)
    }

    // MARK: - Subviews

    private var scrollContent: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                icon
                    .frame(maxWidth: .infinity)
                    .blurSlide(animateIcon)

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .blurSlide(animateTitle)

                cardList
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var cardList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(cards.indices, id: \.self) { index in
                WelcomeCardRow(card: cards[index], tint: tint)
                    .blurSlide(animateCards[index])
            }
        }
    }

    private var actionFooter: some View {
        VStack(spacing: 12) {
            footer

            Button(action: onContinue) {
                Text("开始使用")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                #if os(macOS)
                    .padding(.vertical, 8)
                #else
                    .padding(.vertical, 6)
                #endif
            }
            .tint(tint)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .blurSlide(animateFooter)
        // 仅 footer/按钮 受动画门控,scroll 区域始终可滚动
        .allowsHitTesting(animateFooter)
    }

    // MARK: - Actions

    private func runAnimations() async {
        guard !animateIcon else { return }

        await delayedAnimation(0.35) {
            animateIcon = true
        }

        await delayedAnimation(0.2) {
            animateTitle = true
        }

        try? await Task.sleep(for: .seconds(0.2))

        for index in animateCards.indices {
            let delay = Double(index) * 0.1
            await delayedAnimation(delay) {
                animateCards[index] = true
            }
        }

        await delayedAnimation(0.2) {
            animateFooter = true
        }
    }

    private func delayedAnimation(_ delay: Double, action: @escaping () -> Void) async {
        try? await Task.sleep(for: .seconds(delay))

        withAnimation(.smooth) {
            action()
        }
    }
}

// MARK: - Card Row

private struct WelcomeCardRow: View {
    let card: WelcomeCard
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: card.symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .symbolVariant(.fill)
                .frame(width: 40, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(card.subTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Modifiers

extension View {
    @ViewBuilder
    func blurSlide(_ show: Bool) -> some View {
        self
            .compositingGroup()
            .blur(radius: show ? 0 : 10)
            .opacity(show ? 1 : 0)
            .offset(y: show ? 0 : 100)
    }

    @ViewBuilder
    fileprivate func setUpOnBoarding(usesResizableLayout: Bool) -> some View {
        #if os(macOS)
        self
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(minHeight: 520)
        #elseif os(iOS)
        self.modifier(WelcomeLayoutModifier(usesResizableLayout: usesResizableLayout))
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            self
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        } else {
            self
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        #endif
    }
}

#if os(iOS)
private struct WelcomeLayoutModifier: ViewModifier {
    let usesResizableLayout: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        let usesWideLayout = usesResizableLayout
            ? horizontalSizeClass == .regular
            : UIDevice.current.userInterfaceIdiom == .pad

        content
            .padding(.horizontal, usesWideLayout ? 28 : 20)
            .padding(.top, 12)
            .padding(.bottom, usesWideLayout ? 12 : 8)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
    }
}
#endif

#Preview {
    Text("")
        .sheet(isPresented: .constant(true)) {
            WelcomeView(onContinue: {})
        }
}
