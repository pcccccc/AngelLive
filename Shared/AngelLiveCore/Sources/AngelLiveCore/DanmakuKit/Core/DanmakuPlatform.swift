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

#if os(tvOS)
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
#endif

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

// 注:此处曾有一套模拟 UIGraphicsBeginImageContextWithOptions 语义的 macOS shim
// (全局 DanmakuGraphicsContextStack + 4 个 UIGraphics* 函数)。macOS 的
// DanmakuAsyncLayer 自移植起即走 NSImage.lockFocus 路线,shim 全仓库零调用,
// 且其"全局共享栈 + 16 条并发绘制队列"的设计存在拿错 context 的竞态
// (NSLock 只防崩不防语义,正解本应是线程本地栈,如 UIKit 原生实现)。
// 死代码不修,已整体删除;若未来 macOS 需要 UIGraphics 风格 shim,必须按线程本地实现。
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
