//
//  DanmakuAsyncLayer.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/16.
//

import Foundation
import QuartzCore
import os.lock
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 内部状态全部收在 `OSAllocatedUnfairLock` 里,该类型自身即 `Sendable`,
/// 故本类无需 `@unchecked` 逃生舱。
final class Sentinel: Sendable {

    private let lock = OSAllocatedUnfairLock(initialState: Int32(0))

    public func getValue() -> Int32 {
        lock.withLock { $0 }
    }

    public func increase() {
        lock.withLock { $0 += 1 }
    }

}

/// 注意:不要给本类标 `@unchecked Sendable`——SDK 把 `CALayer: Sendable` 显式标为
/// unavailable,子类的 conformance 会被 SIL 层 region 分析忽略(Sema 层却接受),
/// 等于一个只会误导读者的死声明。跨隔离域传递见下方 `WeakLayerRef`。
public class DanmakuAsyncLayer: CALayer {
    
    /// When true, it is drawn asynchronously and is ture by default.
    public var displayAsync = true
    #if os(macOS)
    var usesBitmapRendering = false
    #endif
    
    public var willDisplay: ((_ layer: DanmakuAsyncLayer) -> Void)?
    
    public var displaying: (@Sendable (_ context: CGContext, _ size: CGSize, _ isCancelled: @Sendable () -> Bool) -> Void)?
    
    public var didDisplay: ((_ layer: DanmakuAsyncLayer, _ finished: Bool) -> Void)?
    
    /// The number of queues to draw the danmaku.
    nonisolated(unsafe) public static var drawDanmakuQueueCount = 16 {
        didSet {
            guard drawDanmakuQueueCount != oldValue else { return }
            pool = nil
            createPoolIfNeed()
        }
    }

    private let sentinel = Sentinel()

    nonisolated(unsafe) private static var pool: DanmakuQueuePool?
    
    override init() {
        super.init()
#if !os(iOS)
        contentsScale = danmakuScreenScale()
#endif
    }
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        sentinel.increase()
    }
    
    public override func setNeedsDisplay() {
        //1. Cancel the last drawing
        sentinel.increase()
        //2. call super
        super.setNeedsDisplay()
    }
    
    public override func display() {
        display(isAsync: displayAsync)
    }
    
    private func display(isAsync: Bool) {
        guard displaying != nil else {
            willDisplay?(self)
            contents = nil
            didDisplay?(self, true)
            return
        }
        
        if isAsync {
            willDisplay?(self)
            let value = sentinel.getValue()
            let sentinel = self.sentinel
            let isCancelled: @Sendable () -> Bool = {
                return value != sentinel.getValue()
            }
            let size = bounds.size
            let scale = contentsScale
            let opaque = isOpaque
            #if os(macOS)
            let usesBitmapRendering = self.usesBitmapRendering
            #endif
            let backgroundColor = (opaque && self.backgroundColor != nil) ? self.backgroundColor : nil
            let displaying = self.displaying
            let queue = self.queue
            // CALayer 的 Sendable conformance 被 SDK 标为 unavailable,子类无法自证 Sendable,
            // 只能用弱引用盒携带 self 穿过绘制队列;盒内引用仅在主 actor 闭包里解包使用,
            // 与 CALayer 的主线程契约一致。
            let ref = WeakLayerRef(layer: self)
            let finish: @MainActor @Sendable (_ image: CGImage?, _ drawn: Bool) -> Void = { image, drawn in
                guard let self = ref.layer else { return }
                if drawn, !isCancelled() {
                    self.contents = image
                    self.didDisplay?(self, true)
                } else {
                    self.didDisplay?(self, false)
                }
            }
            queue.async {
                guard !isCancelled() else { return }
                func draw(in context: CGContext) {
                    if opaque {
                        context.saveGState()
                        let rect = CGRect(origin: .zero, size: size)
                        if backgroundColor == nil || (backgroundColor?.alpha ?? 0) < 1 {
                            context.setFillColor(DanmakuColor.white.cgColor)
                            context.fill(rect)
                        }
                        if let backgroundColor {
                            context.setFillColor(backgroundColor)
                            context.fill(rect)
                        }
                        context.restoreGState()
                    }
                    displaying?(context, size, isCancelled)
                }
#if os(iOS) || os(tvOS)
                UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
                guard let context = UIGraphicsGetCurrentContext() else {
                    UIGraphicsEndImageContext()
                    return
                }
                draw(in: context)
                let cgImage = isCancelled() ? nil : UIGraphicsGetImageFromCurrentImageContext()?.danmakuCGImage
                UIGraphicsEndImageContext()
#elseif os(macOS)
                let cgImage = Self.macImage(size: size, scale: scale, usesBitmap: usesBitmapRendering, draw: draw)
#endif
                if isCancelled() {
                    DispatchQueue.main.async { finish(nil, false) }
                    return
                }
                DispatchQueue.main.async { finish(cgImage, true) }
            }
            
        } else {
            sentinel.increase()
            willDisplay?(self)
#if os(iOS) || os(tvOS)
            UIGraphicsBeginImageContextWithOptions(bounds.size, isOpaque, contentsScale)
            guard let context = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return
            }
            displaying?(context, bounds.size, {() -> Bool in return false})
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            contents = image?.danmakuCGImage
#elseif os(macOS)
            contents = Self.macImage(size: bounds.size, scale: contentsScale, usesBitmap: usesBitmapRendering) { context in
                displaying?(context, bounds.size, {() -> Bool in return false})
            }
#endif
            didDisplay?(self, true)
        }
    }
    
    #if os(macOS)
    private static func macImage(size: CGSize, scale: CGFloat, usesBitmap: Bool, draw: (CGContext) -> Void) -> CGImage? {
        guard usesBitmap else {
            let image = NSImage(size: size)
            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext { draw(context) }
            image.unlockFocus()
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard let width = Int(exactly: ceil(size.width * scale)), width > 0,
              let height = Int(exactly: ceil(size.height * scale)), height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        draw(context)
        return context.makeImage()
    }
    #endif

    /// 跨隔离域携带 layer 弱引用的转移盒。仅限本文件内、且仅在 `@MainActor` 闭包中解包,
    /// 禁止外移或在后台队列解包——安全依据是 CALayer 状态只在主线程读写的既有契约。
    private struct WeakLayerRef: @unchecked Sendable {
        weak var layer: DanmakuAsyncLayer?
    }

    private static func createPoolIfNeed() {
        guard DanmakuAsyncLayer.pool == nil else { return }
        DanmakuAsyncLayer.pool = DanmakuQueuePool(name: "com.DanmakuKit.DanmakuAsynclayer", queueCount: DanmakuAsyncLayer.drawDanmakuQueueCount, qos: .userInteractive)
    }

    private var queue: DispatchQueue {
        DanmakuAsyncLayer.createPoolIfNeed()
        return DanmakuAsyncLayer.pool?.queue ?? DispatchQueue(label: "com.DanmakuKit.DanmakuAsynclayer")
    }
    
}
