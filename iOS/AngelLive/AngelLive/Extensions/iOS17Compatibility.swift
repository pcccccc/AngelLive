//
//  iOS17Compatibility.swift
//  AngelLive
//
//  iOS 17 兼容性修饰符
//

import SwiftUI

/// iOS 版本兼容的 zoom 过渡修饰符
struct ZoomTransitionModifier: ViewModifier {
    let sourceID: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

/// iOS 版本兼容的 matchedTransitionSource 修饰符
struct MatchedTransitionSourceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// iOS 版本兼容的 presentationSizing 修饰符
struct WelcomePresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page.fitted(horizontal: true, vertical: false))
        } else {
            content
        }
    }
}
