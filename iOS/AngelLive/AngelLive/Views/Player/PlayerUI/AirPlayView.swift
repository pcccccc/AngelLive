//
//  AirPlayView.swift
//  KSPlayer
//
//  Created by kintan on 2023/5/4.
//

import AVKit
import SwiftUI

#if !os(visionOS)
public struct AirPlayView: UIViewRepresentable {
    public init() {}

    #if canImport(UIKit)
    public typealias UIViewType = AVRoutePickerView
    public func makeUIView(context _: Context) -> UIViewType {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = UIColor.secondaryLabel
        return routePickerView
    }

    public func updateUIView(_: UIViewType, context _: Context) {}
    #else
    public typealias NSViewType = AVRoutePickerView
    public func makeNSView(context _: Context) -> NSViewType {
        let routePickerView = AVRoutePickerView()
        routePickerView.isRoutePickerButtonBordered = false
        return routePickerView
    }

    public func updateNSView(_: NSViewType, context _: Context) {}
    #endif
}
#endif
