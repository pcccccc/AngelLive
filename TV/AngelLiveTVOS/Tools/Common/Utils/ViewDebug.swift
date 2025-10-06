//
//  View.swift
//  SyncNext
//
//  Created by 黃佁媛 on 2021/10/28.
//

// Text("debug")
//    .debugOnlyBackground()
//
// Text("debug")
//    .debugOnlyBorder()

import Foundation
import SwiftUI

extension View {
    func debugOnlyModifier<T: View>(_ modifier: (Self) -> T) -> some View {
        #if DEBUG
            return modifier(self)
        #else
            return self
        #endif
    }

    private var colors: [Color] {
        [.blue, .yellow, .green, .red, .brown, .cyan, .gray, .indigo, .mint, .pink, .orange]
    }

    func debugOnlyBackground() -> some View {
        debugOnlyModifier {
            $0.background(Rectangle().foregroundColor(colors.randomElement()?.opacity(0.25)))
        }
    }

    func debugOnlyBorder() -> some View {
        debugOnlyModifier {
            $0.border(colors.randomElement() ?? Color.black, width: 1)
        }
    }

    func debugPrintSize(_ title: String = "Print Size") -> some View {
        debugOnlyModifier {
            $0.readSize { size in
                print("\(title) -> size", size.debugDescription)
            }
        }
    }
}

extension View {
    func os16Modifier<T: View>(_ modifier: (Self) -> T) -> some View {
        if #available(tvOS 16.0, *) {
            return modifier(self)
        } else {
            return self
        }
    }

    func os15Modifier<T: View>(_ modifier: (Self) -> T) -> some View {
        if #available(tvOS 15.0, *) {
            return modifier(self)
        } else {
            return self
        }
    }
}

extension View {
    func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}
