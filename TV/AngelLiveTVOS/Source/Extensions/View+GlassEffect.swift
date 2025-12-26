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
            self.glassEffect(.regular.interactive().tint(.black.opacity(0.6)))
        } else {
            self.background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    func adaptiveGlassEffectCapsule() -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect(.regular.interactive().tint(.black.opacity(0.6)), in: .capsule)
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
            self.glassEffect(.regular.interactive().tint(.black.opacity(0.6)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius)
            )
        }
    }
}
