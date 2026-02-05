//
//  DanmakuPlatform.swift
//  AngelLiveCore
//
//  Shared abstractions to make DanmakuKit available on UIKit/AppKit.
//

import Foundation
import CoreGraphics

#if os(iOS) || os(tvOS)
import UIKit
public typealias DanmakuBaseView = UIView
public typealias DanmakuColor = UIColor
public typealias DanmakuFont = UIFont
public typealias DanmakuImage = UIImage
public typealias DanmakuEvent = UIEvent
public typealias DanmakuTapGestureRecognizer = UITapGestureRecognizer

/// Cached screen scale to avoid MainActor access from background threads
nonisolated(unsafe) private var cachedScreenScale: CGFloat = 0

private func initScreenScaleIfNeeded() {
    guard cachedScreenScale == 0 else { return }
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            cachedScreenScale = UIScreen.main.scale
        }
    } else {
        DispatchQueue.main.sync {
            cachedScreenScale = UIScreen.main.scale
        }
    }
}

func danmakuScreenScale() -> CGFloat {
    initScreenScaleIfNeeded()
    return cachedScreenScale
}

public extension UIView {
    var danmakuBackgroundColor: UIColor? {
        get { backgroundColor }
        set { backgroundColor = newValue }
    }

    var danmakuCenter: CGPoint {
        get { center }
        set { center = newValue }
    }
}

public extension UIImage {
    var danmakuScale: CGFloat { scale }
    var danmakuCGImage: CGImage? { cgImage }
}

public extension UIColor {
    func danmakuGetRGBA(_ red: inout CGFloat, _ green: inout CGFloat, _ blue: inout CGFloat, _ alpha: inout CGFloat) -> Bool {
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    }
}

extension UIFont {
    var danmakuLineHeight: CGFloat { lineHeight }
}
#elseif os(macOS)
import AppKit
import QuartzCore
public typealias DanmakuBaseView = NSView
public typealias DanmakuColor = NSColor
public typealias DanmakuFont = NSFont
public typealias DanmakuImage = NSImage
public typealias DanmakuEvent = NSEvent
public typealias DanmakuTapGestureRecognizer = NSClickGestureRecognizer

/// Cached screen scale to avoid MainActor access from background threads
nonisolated(unsafe) private var cachedScreenScale: CGFloat = 0

private func initScreenScaleIfNeeded() {
    guard cachedScreenScale == 0 else { return }
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            cachedScreenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        }
    } else {
        DispatchQueue.main.sync {
            cachedScreenScale = NSScreen.main?.backingScaleFactor ?? 2.0
        }
    }
}

func danmakuScreenScale() -> CGFloat {
    initScreenScaleIfNeeded()
    return cachedScreenScale
}

public extension NSView {
    var danmakuBackgroundColor: NSColor? {
        get {
            guard let cgColor = layer?.backgroundColor else { return nil }
            return NSColor(cgColor: cgColor)
        }
        set {
            wantsLayer = true
            layer?.backgroundColor = newValue?.cgColor
        }
    }

    var danmakuCenter: CGPoint {
        get { CGPoint(x: frame.midX, y: frame.midY) }
        set {
            frame.origin = CGPoint(x: newValue.x - frame.size.width / 2.0,
                                   y: newValue.y - frame.size.height / 2.0)
        }
    }
}

public extension NSImage {
    var danmakuScale: CGFloat { cachedScreenScale }
    var danmakuCGImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

extension NSFont {
    var danmakuLineHeight: CGFloat { ascender - descender + leading }
}

public extension NSColor {
    func danmakuGetRGBA(_ red: inout CGFloat, _ green: inout CGFloat, _ blue: inout CGFloat, _ alpha: inout CGFloat) -> Bool {
        guard let converted = usingColorSpace(.deviceRGB) else { return false }
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return true
    }
}

private struct DanmakuGraphicsContext {
    let context: CGContext
    let size: CGSize
    let scale: CGFloat
}

private final class DanmakuGraphicsContextStack: @unchecked Sendable {
    private var stack: [DanmakuGraphicsContext] = []
    private let lock = NSLock()

    func push(_ state: DanmakuGraphicsContext) {
        lock.lock()
        stack.append(state)
        lock.unlock()
    }

    func current() -> DanmakuGraphicsContext? {
        lock.lock()
        let value = stack.last
        lock.unlock()
        return value
    }

    @discardableResult
    func pop() -> DanmakuGraphicsContext? {
        lock.lock()
        let value = stack.popLast()
        lock.unlock()
        return value
    }
}

private let danmakuContextStack = DanmakuGraphicsContextStack()

func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
    let resolvedScale = scale == 0 ? danmakuScreenScale() : scale
    let width = max(Int(size.width * resolvedScale), 1)
    let height = max(Int(size.height * resolvedScale), 1)
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return }
    context.scaleBy(x: resolvedScale, y: resolvedScale)
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    danmakuContextStack.push(DanmakuGraphicsContext(context: context, size: size, scale: resolvedScale))
}

func UIGraphicsGetCurrentContext() -> CGContext? {
    danmakuContextStack.current()?.context
}

func UIGraphicsGetImageFromCurrentImageContext() -> NSImage? {
    guard let state = danmakuContextStack.current(),
          let cgImage = state.context.makeImage() else { return nil }
    let nsSize = NSSize(width: state.size.width, height: state.size.height)
    return NSImage(cgImage: cgImage, size: nsSize)
}

func UIGraphicsEndImageContext() {
    _ = danmakuContextStack.pop()
}
#endif

#if os(iOS) || os(tvOS)
func makeDanmakuImage(from cgImage: CGImage, scale: CGFloat) -> UIImage {
    UIImage(cgImage: cgImage, scale: scale, orientation: .up)
}
#else
func makeDanmakuImage(from cgImage: CGImage, scale: CGFloat) -> NSImage {
    let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
    return NSImage(cgImage: cgImage, size: size)
}
#endif
