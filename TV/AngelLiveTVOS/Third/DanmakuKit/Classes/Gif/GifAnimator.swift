//
//  GifAnimator.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2021/9/3.
//

import UIKit

/// This is a class for managing GIF animations.
/// If you want to customize GIF DanmakuCell, you can refer to this class or use it.
public class GifAnimator {
    
    /// Total animation frames.
    public private(set) var frameCount: Int = 0
    
    /// The duration of an animation loop.
    public private(set) var loopDuration: TimeInterval = 0
    
    /// The maximum duration of an animation frame, default is 1.0s.
    public var maxFrameDuration: TimeInterval = 1.0
    
    /// Decode image in background, default is true.
    public var backgroundDecode = true
    
    public var isLastFrame: Bool {
        return currentFrameIndex == frameCount - 1
    }
    
    public private(set) var currentFrameIndex = 0 {
        didSet {
            previousFrameIndex = oldValue
        }
    }
    
    public var currentFrameImage: UIImage? {
        return frames[currentFrameIndex]?.image
    }
    
    /// The duration of the current frame.
    public var currentFrameDuration: TimeInterval {
        return frames[currentFrameIndex]?.duration  ?? .infinity
    }
    
    /// Called when the GIF animation has finished playing.
    public var didFinishAnimation: (() -> Void)?
    
    /// When the screen is updated, the image that should be displayed in the GIF is returned.
    public var update: ((_: UIImage?) -> Void)?
    
    private let imageSource: CGImageSource
    
    private let preloadCount: Int
    
    private let imageSize: CGSize
    
    private let imageScale: CGFloat
    
    private let maxRepeatCount: Int
    
    private var frames = SafeArray<GifFrame>()
    
    private var currentRepeatCount: UInt = 0
    
    private var timeSinceLastFrameChange: TimeInterval = 0.0

    private var previousFrameIndex = 0 {
        didSet {
            queue.async { [weak self] in
                autoreleasepool {
                    self?.updatePreloadedFrames()
                }
            }
        }
    }
    
    private var isReachMaxRepeatCount: Bool {
        return currentRepeatCount >= maxRepeatCount
    }
    
    private static var pool: DanmakuQueuePool?
    
    public init(imageSource source: CGImageSource,
                preloadCount count: Int,
                imageSize size: CGSize,
                imageScale scale: CGFloat,
                maxRepeatCount repeatCount: Int) {
        imageSource = source
        preloadCount = count
        imageSize = size
        imageScale = scale
        maxRepeatCount = repeatCount
    }
    
    deinit {
        displayLink.invalidate()
    }
    
    /// Prepare GIF resource.
    public func prepare() {
        frameCount = CGImageSourceGetCount(imageSource)
        frames.reserveCapacity(frameCount)
        queue.async { [weak self] in
            self?.setupAsync()
        }
    }
    
    public func startAnimation() {
        displayLink.isPaused = false
    }
    
    public func stopAnimation() {
        displayLink.isPaused = true
        didFinishAnimation?()
    }
    
    private func setupAsync() {
        frames.removeAll()
        
        var duration: TimeInterval = 0
        for i in 0..<frameCount {
            let frameDuration = GifAnimator.getFrameDuration(from: imageSource, at: i)
            duration += min(frameDuration, maxFrameDuration)
            if i > preloadCount {
                frames.append(GifFrame(image: nil, duration: frameDuration))
                break
            } else {
                //获取需要预加载的每一帧图片
                frames.append(GifFrame(image: frame(at: i), duration: frameDuration))
            }
        }
        
        loopDuration = duration
    }
    
    private func onScreenUpdate() {
        let duration: CFTimeInterval
        if #available(iOS 10.0, *) {
            let preferredFramesPerSecond = displayLink.preferredFramesPerSecond
            if preferredFramesPerSecond == 0 {
                duration = displayLink.duration
            } else {
                duration = 1.0 / TimeInterval(preferredFramesPerSecond)
            }
        } else {
            duration = displayLink.duration
        }
        
        //累加屏幕更新时长，直到时长超过一帧动画的时长
        timeSinceLastFrameChange += min(maxFrameDuration, duration)
        guard timeSinceLastFrameChange >= currentFrameDuration else { return }
        
        //屏幕刷新时间达到动画一帧的时间，开始更新GIF图片
        timeSinceLastFrameChange -= currentFrameDuration
        currentFrameIndex = increment(frameIndex: currentFrameIndex)
        if isLastFrame {
            //如果当前是最后一帧
            currentRepeatCount += 1
            if isReachMaxRepeatCount {
                //且达到重复上限，那么停止动画
                stopAnimation()
            }
        }
        
        update?(currentFrameImage)
    }
    
    private func frame(at index: Int) -> UIImage? {
        let resize = imageSize != .zero
        let options: [CFString: Any]?
        if resize {
            options = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(imageSize.width, imageSize.height)
            ]
        } else {
            options = nil
        }
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary?) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        
        if backgroundDecode {
            //后台强制解码图片
            UIGraphicsBeginImageContextWithOptions(imageSize, false, imageScale)
            guard let context = UIGraphicsGetCurrentContext() else { return image }
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: 0, y: -imageSize.height)
            
            let size = CGSize(width: CGFloat(cgImage.width) / imageScale, height: CGFloat(cgImage.height) / imageScale)
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))

            guard let cgImage = context.makeImage() else { return image }
            
            UIGraphicsEndImageContext()
            
            return UIImage(cgImage: cgImage, scale: imageScale, orientation: image.imageOrientation)
        } else {
            return image
        }
    }
    
    private func updatePreloadedFrames() {
        //1.移除使用过图片，减轻内存压力
        frames[previousFrameIndex] = frames[previousFrameIndex]?.placeholderFrame
        
        //2.预加载后续Gif图片
        preloadIndexes(start: currentFrameIndex).forEach { index in
            guard let currentFrame = frames[index] else { return }
            guard currentFrame.isPlaceholder else { return }
            frames[index] = GifFrame(image: frame(at: index), duration: currentFrame.duration)
        }
    }
    
    private func increment(frameIndex: Int, by value: Int = 1) -> Int {
        return (frameIndex + value) % frameCount
    }
    
    private func preloadIndexes(start index: Int) -> [Int] {
        let nextIndex = increment(frameIndex: index)
        let lastIndex = increment(frameIndex: index, by: preloadCount)

        if lastIndex >= nextIndex {
            return [Int](nextIndex...lastIndex)
        } else {
            return [Int](nextIndex..<frameCount) + [Int](0...lastIndex)
        }
    }
    
    private static func getFrameDuration(from imageSource: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String: Any] else { return 0.0 }
        let defaultFrameDuration = 0.1
        guard let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] else { return defaultFrameDuration }
        let unclampedDelayTime = gifInfo[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber
        let delayTime = gifInfo[kCGImagePropertyGIFDelayTime as String] as? NSNumber
        let duration = unclampedDelayTime ?? delayTime
        
        guard let frameDuration = duration else { return defaultFrameDuration }
        return frameDuration.doubleValue > 0.011 ? frameDuration.doubleValue : defaultFrameDuration
    }
    
    private func createPoolIfNeeded() {
        guard GifAnimator.pool == nil else { return }
        GifAnimator.pool = DanmakuQueuePool(name: "com.DanmakuKit.GifAnimator", queueCount: 8, qos: .userInteractive)
    }
    
    private lazy var queue: DispatchQueue = {
        createPoolIfNeeded()
        return GifAnimator.pool?.queue ?? DispatchQueue(label: "com.DanmakuKit.GifAnimator")
    }()
    
    private lazy var displayLink: CADisplayLink = {
        let displayLink = CADisplayLink(target: TargetProxy(target: self), selector: #selector(TargetProxy.onScreenUpdate))
        displayLink.add(to: .main, forMode: .common)
        displayLink.isPaused = true
        return displayLink
    }()
    
}

//MARK: TargetProxy

extension GifAnimator {
    
    class TargetProxy: NSObject {
        
        private weak var target: GifAnimator?
        
        init(target: GifAnimator) {
            self.target = target
        }
        
        @objc func onScreenUpdate() {
            target?.onScreenUpdate()
        }
        
    }
    
}

//MARK: GifFrame

extension GifAnimator {
    
    struct GifFrame {
        
        let image: UIImage?
        
        let duration: TimeInterval
        
        var isPlaceholder: Bool {
            return image == nil
        }
        
        var placeholderFrame: GifFrame {
            return GifFrame(image: nil, duration: duration)
        }
        
    }
    
}

fileprivate class SafeArray<Element> {
    
    private var array: Array<Element> = []
    private let lock = NSLock()
    
    subscript(index: Int) -> Element? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return array.indices ~= index ? array[index] : nil
        }
        
        set {
            lock.lock()
            defer { lock.unlock() }
            if let newValue = newValue, array.indices ~= index {
                array[index] = newValue
            }
        }
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return array.count
    }
    
    func reserveCapacity(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        array.reserveCapacity(count)
    }
    
    func append(_ element: Element) {
        lock.lock()
        defer { lock.unlock() }
        array += [element]
    }
    
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        array = []
    }
}
