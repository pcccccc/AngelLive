//
//  View+GlassEffect.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2025/11/20.
//

import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlassEffect() -> some View {
        if #available(tvOS 26.0, *) {
            self.glassEffect(in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
