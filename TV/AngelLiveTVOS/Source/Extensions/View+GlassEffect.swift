//
//  View+GlassEffect.swift
//  AngelLive
//
//  Created by some developer on 2024/9/15.
//

import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlassEffect() -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect()
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    func adaptiveGlassEffectCapsule() -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect(in: .capsule)
        } else {
            self.background(
                .ultraThinMaterial,
                in: Capsule()
            )
        }
    }

    @ViewBuilder
    func adaptiveGlassEffectRoundedRect(cornerRadius: CGFloat = 16) -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
        }
    }
}
