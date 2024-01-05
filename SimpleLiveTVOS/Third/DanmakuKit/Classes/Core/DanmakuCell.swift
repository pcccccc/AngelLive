//
//  DanmakuCell.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2020/8/16.
//

import UIKit

open class DanmakuCell: UIView {

    public var model: DanmakuCellModel?
    
    public internal(set) var animationTime: TimeInterval = 0
    
    var animationBeginTime: TimeInterval = 0
    
    public override class var layerClass: AnyClass {
        return DanmakuAsyncLayer.self
    }
    
    public required override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Overriding this method, you can get the timing before the content rendering.
    open func willDisplay() {}
    
    
    /// Overriding this method to draw danmaku.
    /// - Parameters:
    ///   - context: drawing context
    ///   - size: bounds.size
    ///   - isCancelled: Whether drawing is cancelled
    open func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {}
    
    /// Overriding this method, you can get the timing after the content rendering.
    /// - Parameter finished: False if draw is cancelled
    open func didDisplay(_ finished: Bool) {}
    
    /// Overriding this method, you can get th timing of danmaku enter track.
    open func enterTrack() {}
    
    /// Overriding this method, you can get th timing of danmaku leave track.
    open func leaveTrack() {}
    
    /// Decide whether to use asynchronous rendering.
    public var displayAsync = true {
        didSet {
            guard let layer = layer as? DanmakuAsyncLayer else { return }
            layer.displayAsync = displayAsync
        }
    }
    
    /// This method can trigger the rendering process, the content can be re-rendered in the displaying(_:_:_:) method.
    public func redraw() {
        layer.setNeedsDisplay()
    }
       
}

extension DanmakuCell {
    
    var realFrame: CGRect {
        if layer.presentation() != nil {
            return layer.presentation()!.frame
        } else {
            return frame
        }
    }
    
    func setupLayer() {
        guard let layer = layer as? DanmakuAsyncLayer else { return }
        
        layer.contentsScale = UIScreen.main.scale
        
        layer.willDisplay = { [weak self] (layer) in
            guard let strongSelf = self else { return }
            strongSelf.willDisplay()
        }
        
        layer.displaying = { [weak self] (context, size, isCancelled) in
            guard let strongSelf = self else { return }
            strongSelf.displaying(context, size, isCancelled())
        }
        
        layer.didDisplay = { [weak self] (layer, finished) in
            guard let strongSelf = self else { return }
            strongSelf.didDisplay(finished)
        }
    }
    
}
