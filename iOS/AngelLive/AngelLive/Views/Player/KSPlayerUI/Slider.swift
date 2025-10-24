//
//  Slider.swift
//  KSPlayer
//
//  Created by kintan on 2023/5/4.
//

import Foundation
import SwiftUI

#if os(tvOS)
import Combine

@available(tvOS 15.0, *)
public struct Slider: View {
    private let value: Binding<Float>
    private let bounds: ClosedRange<Float>
    private let onEditingChanged: (Bool) -> Void
    @FocusState
    private var isFocused: Bool
    public init(value: Binding<Float>, in bounds: ClosedRange<Float> = 0 ... 1, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.value = value
        self.bounds = bounds
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        ZStack {
            TVOSSlide(value: value, bounds: bounds, isFocused: _isFocused, onEditingChanged: onEditingChanged)
                .focused($isFocused)
            ProgressView(value: value.wrappedValue, total: bounds.upperBound)
        }
    }
}

@available(tvOS 15.0, *)
public struct TVOSSlide: UIViewRepresentable {
    fileprivate let value: Binding<Float>
    fileprivate let bounds: ClosedRange<Float>
    @FocusState
    public var isFocused: Bool
    public let onEditingChanged: (Bool) -> Void
    public typealias UIViewType = TVSlide
    public init(value: Binding<Float>, bounds: ClosedRange<Float>, isFocused: FocusState<Bool>, onEditingChanged: @escaping (Bool) -> Void) {
        self.value = value
        self.bounds = bounds
        _isFocused = isFocused
        self.onEditingChanged = onEditingChanged
    }

    public func makeUIView(context _: Context) -> UIViewType {
        TVSlide(value: value, bounds: bounds, onEditingChanged: onEditingChanged)
    }

    public func updateUIView(_ view: UIViewType, context _: Context) {
        if !isFocused {
            view.cancle()
        }
    }
}

public class TVSlide: UIControl {
    private var beganValue: Float
    private let onEditingChanged: (Bool) -> Void
    fileprivate var value: Binding<Float>
    fileprivate let ranges: ClosedRange<Float>
    private var moveDirection: UISwipeGestureRecognizer.Direction?
    private var pressTime = CACurrentMediaTime()

    private lazy var timer: Timer = .scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
        guard let self else {
            return
        }
        runOnMainThread { [weak self] in
            guard let self, let moveDirection else {
                return
            }
            let rate = min(10, Int((CACurrentMediaTime() - pressTime) / 2) + 1)
            let wrappedValue = value.wrappedValue + Float((moveDirection == .right ? 10 : -10) * rate)
            if wrappedValue >= ranges.lowerBound, wrappedValue <= ranges.upperBound {
                value.wrappedValue = wrappedValue
            }
        }
    }

    public init(value: Binding<Float>, bounds: ClosedRange<Float>, onEditingChanged: @escaping (Bool) -> Void) {
        self.value = value
        beganValue = value.wrappedValue
        ranges = bounds
        self.onEditingChanged = onEditingChanged
        super.init(frame: .zero)
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(actionPanGesture(sender:)))
        addGestureRecognizer(panGestureRecognizer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func cancle() {
        if timer.fireDate == .distantPast {
            timer.fireDate = .distantFuture
        }
    }

    override open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let presse = presses.first else {
            return
        }
        switch presse.type {
        case .leftArrow:
            moveDirection = .left
            pressTime = CACurrentMediaTime()
            onEditingChanged(true)
            timer.fireDate = .distantPast
        case .rightArrow:
            moveDirection = .right
            pressTime = CACurrentMediaTime()
            onEditingChanged(true)
            timer.fireDate = .distantPast
        case .select:
            timer.fireDate = .distantFuture
            onEditingChanged(false)
        default:
            timer.fireDate = .distantFuture
            if moveDirection != nil, !KSOptions.seekRequireConfirmation {
                onEditingChanged(false)
            }
            super.pressesBegan(presses, with: event)
        }
    }

    @objc private func actionPanGesture(sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .began, .possible:
            timer.fireDate = .distantFuture
            beganValue = value.wrappedValue
            onEditingChanged(true)
        case .changed:
            let translation = sender.translation(in: self)
            if abs(translation.y) > abs(translation.x) {
                return
            }
            let wrappedValue = beganValue + Float(translation.x) / Float(frame.size.width) * (ranges.upperBound - ranges.lowerBound) / 5
            if wrappedValue <= ranges.upperBound, wrappedValue >= ranges.lowerBound {
                value.wrappedValue = wrappedValue
            }
        case .ended:
            beganValue = value.wrappedValue
            if !KSOptions.seekRequireConfirmation {
                onEditingChanged(false)
            }
        case .cancelled, .failed:
//            value.wrappedValue = beganValue
            break
        @unknown default:
            break
        }
    }
}
#endif
