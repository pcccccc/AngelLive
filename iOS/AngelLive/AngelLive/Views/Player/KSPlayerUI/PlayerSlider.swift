//
//  PlayerSlider.swift
//
//  Created by WangJun on 2024/8/21.
//

import Foundation
import SwiftUI

@available(iOS 15, macOS 12, tvOS 15, *)
public struct PlayerSlider: View {
    let value: Binding<Float>
    let bufferValue: Float
    let bounds: ClosedRange<Float>
    let onEditingChanged: (Bool) -> Void
    @State
    private var beginDrag = false
    @FocusState
    private var isFocused: Bool
    @State
    private var hoverValue: Float?
    #if DEBUG
    private var preLoadProtocol: PreLoadProtocol?
    #endif
    public init(model: ControllerTimeModel, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(value: Binding {
            Float(model.currentTime)
        } set: { newValue, _ in
            model.currentTime = Int(newValue)
        }, in: 0 ... Float(model.totalTime), bufferValue: Float(model.bufferTime), onEditingChanged: onEditingChanged)
        #if DEBUG
        preLoadProtocol = model.preLoadProtocol
        #endif
    }

    public init(value: Binding<Float>, in bounds: ClosedRange<Float> = 0 ... 1, bufferValue: Float, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.value = value
        self.bufferValue = bufferValue
        self.bounds = bounds
        self.onEditingChanged = onEditingChanged
        #if DEBUG
        preLoadProtocol = nil
        #endif
    }

    public var body: some View {
        #if os(tvOS)
        ZStack {
            TVOSSlide(value: value, bounds: bounds, isFocused: _isFocused, onEditingChanged: onEditingChanged)
                .focused($isFocused)
            ProgressTrack(value: value, bufferValue: bufferValue, bounds: bounds, progressColor: isFocused ? KSOptions.focusProgressColor : KSOptions.progressColor)
                .allowsHitTesting(false)
        }
        #else
        GeometryReader { geometry in
            #if DEBUG
            if let preLoadProtocol, preLoadProtocol.fileSize() > 0 {
                ForEach(Array(preLoadProtocol.entryList.enumerated()), id: \.offset) { _, entry in
                    Rectangle()
                        .fill(Color.indigo.opacity(0.8))
                        .offset(x: CGFloat(Double(entry.logicalPos) / Double(preLoadProtocol.fileSize())) * geometry.size.width)
                        .frame(width: CGFloat(Double(entry.size) / Double(preLoadProtocol.fileSize())) * geometry.size.width)
                }
                Rectangle()
                    .fill(Color.green)
                    .offset(x: CGFloat(Double(preLoadProtocol.logicalPos) / Double(preLoadProtocol.fileSize())) * geometry.size.width)
                    .frame(width: 3)
            }
            #endif
            // 进度部分
            ProgressTrack(value: value, bufferValue: bufferValue, bounds: bounds, progressColor: KSOptions.progressColor)
                .frame(height: KSOptions.trackHeight)
                .frame(height: KSOptions.interactiveSize.height)
            #if os(macOS)
                .background {
                    // mac上面拖动进度条时整个窗口都会被拖动，这样可以临时解决，以后有更好的方法再改下
                    Button {} label: {
                        Color.clear
                    }
                }
            #else
                .background(.white.opacity(0.001)) // 需要一个背景，不然interactiveSize的触控范围不会生效
            #endif
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gestureValue in
                            let computedValue = valueFrom(
                                distance: Float(gestureValue.location.x),
                                availableDistance: Float(geometry.size.width),
                                bounds: bounds,
                                leadingOffset: Float(KSOptions.thumbSize.width) / 2,
                                trailingOffset: Float(KSOptions.thumbSize.width) / 2
                            )
                            value.wrappedValue = computedValue
                            if !beginDrag {
                                beginDrag = true
                                onEditingChanged(true)
                            }
                        }
                        .onEnded { _ in
                            beginDrag = false
                            onEditingChanged(false)
                        }
                )
                .onHoverActive { point in
                    if let point {
                        hoverValue = Float(point.x)
                    } else {
                        hoverValue = nil
                    }
                }
            if let hoverValue {
                let computedValue = valueFrom(
                    distance: Float(hoverValue),
                    availableDistance: Float(geometry.size.width),
                    bounds: bounds,
                    leadingOffset: Float(KSOptions.thumbSize.width) / 2,
                    trailingOffset: Float(KSOptions.thumbSize.width) / 2
                )
                Text(computedValue.toString(for: .minOrHour))
                    .foregroundColor(.white)
                    .position(x: CGFloat(hoverValue), y: 0)
            }
            // 圆点
            Circle()
                .fill(KSOptions.thumbColor)
                .frame(width: KSOptions.thumbSize.width, height: KSOptions.thumbSize.height)
                .frame(minWidth: KSOptions.interactiveSize.width, minHeight: KSOptions.interactiveSize.height)
                .background(.white.opacity(0.001)) // 需要一个背景，不然interactiveSize的触控范围不会生效
                .position(
                    x: distanceFrom(
                        value: value.wrappedValue,
                        availableDistance: Float(geometry.size.width),
                        bounds: bounds,
                        leadingOffset: Float(KSOptions.thumbSize.width) / 2,
                        trailingOffset: Float(KSOptions.thumbSize.width) / 2
                    ),
                    y: geometry.size.height / 2
                )
                .gesture(
                    DragGesture(minimumDistance: 1) // 这里不要设置成0，不然不小心碰到圆点就会定位
                        .onChanged { gestureValue in
                            let computedValue = valueFrom(
                                distance: Float(gestureValue.location.x),
                                availableDistance: Float(geometry.size.width),
                                bounds: bounds,
                                leadingOffset: Float(KSOptions.thumbSize.width) / 2,
                                trailingOffset: Float(KSOptions.thumbSize.width) / 2
                            )
                            value.wrappedValue = computedValue
                            if !beginDrag {
                                beginDrag = true
                                onEditingChanged(true)
                            }
                        }
                        .onEnded { _ in
                            beginDrag = false
                            onEditingChanged(false)
                        }
                )
        }
        .frame(height: KSOptions.interactiveSize.height)
        #endif
    }
}

@available(iOS 15, macOS 12, tvOS 15, *)
private struct ProgressTrack: View {
    let value: Binding<Float>
    let bufferValue: Float
    let bounds: ClosedRange<Float>
    let progressColor: Color
    @FocusState
    private var isFocused: Bool
    func maskView(geometry: GeometryProxy, value: Float, offset: Float) -> some View {
        Capsule()
            .frame(
                width: distanceFrom(
                    value: value,
                    availableDistance: Float(geometry.size.width),
                    bounds: bounds,
                    leadingOffset: offset,
                    trailingOffset: offset
                )
            )
            .frame(width: geometry.size.width, alignment: .leading)
    }

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(KSOptions.bufferColor).mask(maskView(geometry: geometry, value: bufferValue, offset: 0))
            Capsule().fill(progressColor)
            #if os(tvOS) // TV上面没有圆点，不需要间距
                .mask(maskView(geometry: geometry, value: value.wrappedValue, offset: 0))
            #else
                .mask(maskView(geometry: geometry, value: value.wrappedValue, offset: Float(KSOptions.thumbSize.width) / 2))
            #endif
        }
        .background(KSOptions.trackColor)
        #if os(tvOS)
            .cornerRadius(KSOptions.interactiveSize.height / 2)
        #else
            .cornerRadius(KSOptions.trackHeight)
        #endif
    }
}

public extension KSOptions {
    // MARK: PlayerSlider options

    // tvos的seek是否需要确认键
    @MainActor
    static var seekRequireConfirmation = true
    // 圆点大小
    @MainActor
    static var thumbSize: CGSize = .init(width: 15, height: 15)
    // 交互面积，比圆点要大一些
    #if os(tvOS)
    @MainActor
    static var interactiveSize: CGSize = .init(width: 20, height: 20)
    #else
    @MainActor
    static var interactiveSize: CGSize = .init(width: 25, height: 25)
    #endif
    // 轨道高度
    @MainActor
    static var trackHeight: CGFloat = 5

    // 圆点颜色
    @MainActor
    static var thumbColor = Color.white
    // 轨道颜色
    @MainActor
    static var trackColor = Color.white.opacity(0.5)
    // 播放进度颜色
    @MainActor
    static var progressColor = Color.green.opacity(0.8)
    // 播放进度颜色
    @MainActor
    static var focusProgressColor = Color.red.opacity(0.9)
    // 缓存进度颜色
    @MainActor
    static var bufferColor = Color.white.opacity(0.9)
}

private func distanceFrom(value: Float, availableDistance: Float, bounds: ClosedRange<Float> = 0.0 ... 1.0, leadingOffset: Float = 0, trailingOffset: Float = 0) -> CGFloat {
    guard availableDistance > leadingOffset + trailingOffset, bounds.upperBound > bounds.lowerBound else { return 0 }
    let relativeValue = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
    let offset = (leadingOffset - ((leadingOffset + trailingOffset) * relativeValue))
    return CGFloat(offset + (availableDistance * relativeValue))
}

private func valueFrom(distance: Float, availableDistance: Float, bounds: ClosedRange<Float> = 0.0 ... 1.0, step: Float = 0.001, leadingOffset: Float = 0, trailingOffset: Float = 0) -> Float {
    let relativeValue = (distance - leadingOffset) / (availableDistance - (leadingOffset + trailingOffset))
    let newValue = bounds.lowerBound + (relativeValue * (bounds.upperBound - bounds.lowerBound))
    let steppedNewValue = (round(newValue / step) * step)
    let validatedValue = min(bounds.upperBound, max(bounds.lowerBound, steppedNewValue))
    return validatedValue
}

#if DEBUG
@available(iOS 15, macOS 12, tvOS 15, *)
struct PlayerSlider_Previews: PreviewProvider {
    static var previews: some View {
        let model = ControllerTimeModel()
        model.currentTime = 50
        model.bufferTime = 75
        model.totalTime = 100
        return PlayerSlider(model: model)
    }
}
#endif
