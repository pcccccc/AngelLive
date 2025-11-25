//
//  DanmakuAsyncLayer.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/16.
//

import Foundation
import QuartzCore
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class Sentinel {
    
    private var value: Int32 = 0
    
    public func getValue() -> Int32 {
        return value
    }
    
    public func increase() {
        let p = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        p.pointee = value
        OSAtomicIncrement32(p)
        p.deallocate()
    }
    
}

public class DanmakuAsyncLayer: CALayer {
    
    /// When true, it is drawn asynchronously and is ture by default.
    public var displayAsync = true
    
    public var willDisplay: ((_ layer: DanmakuAsyncLayer) -> Void)?
    
    public var displaying: ((_ context: CGContext, _ size: CGSize, _ isCancelled:(() -> Bool)) -> Void)?
    
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
        contentsScale = danmakuScreenScale()
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
            let isCancelled = {() -> Bool in
                return value != self.sentinel.getValue()
            }
            let size = bounds.size
            let scale = contentsScale
            let opaque = isOpaque
            let backgroundColor = (opaque && self.backgroundColor != nil) ? self.backgroundColor : nil
            queue.async {
                guard !isCancelled() else { return }
#if os(iOS) || os(tvOS)
                UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
                guard let context = UIGraphicsGetCurrentContext() else {
                    UIGraphicsEndImageContext()
                    return
                }
#elseif os(macOS)
                // macOS: 创建离屏 NSImage 并获取 context
                let image = NSImage(size: size)
                image.lockFocus()
                guard let context = NSGraphicsContext.current?.cgContext else {
                    image.unlockFocus()
                    return
                }
#endif
                if opaque {
                    context.saveGState()
                    if backgroundColor == nil || (backgroundColor?.alpha ?? 0) < 1 {
                        context.setFillColor(DanmakuColor.white.cgColor)
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    if let backgroundColor = backgroundColor {
                        context.setFillColor(backgroundColor)
                        context.addRect(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
                        context.fillPath()
                    }
                    context.restoreGState()
                }
                self.displaying?(context, size, isCancelled)
                if isCancelled() {
#if os(iOS) || os(tvOS)
                    UIGraphicsEndImageContext()
#elseif os(macOS)
                    image.unlockFocus()
#endif
                    DispatchQueue.main.async {
                        self.didDisplay?(self, false)
                    }
                    return
                }
#if os(iOS) || os(tvOS)
                let image = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
#elseif os(macOS)
                image.unlockFocus()
                let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
#endif
                if isCancelled() {
                    DispatchQueue.main.async {
                        self.didDisplay?(self, false)
                    }
                    return
                }
                DispatchQueue.main.async {
                    if isCancelled() {
                        self.didDisplay?(self, false)
                    } else {
#if os(iOS) || os(tvOS)
                        self.contents = image?.danmakuCGImage
#elseif os(macOS)
                        self.contents = cgImage
#endif
                        self.didDisplay?(self, true)
                    }
                }
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
            let image = NSImage(size: bounds.size)
            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                displaying?(context, bounds.size, {() -> Bool in return false})
            }
            image.unlockFocus()
            contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
#endif
            didDisplay?(self, true)
        }
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
