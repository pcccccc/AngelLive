//
//  DanmakuGifCellModel.swift
//  DanmakuKit
//
//  Created by Q YiZhong on 2021/8/31.
//

import Foundation

public protocol DanmakuGifCellModel: DanmakuCellModel {
    
    /// GIF data source
    var resource: Data? { get }
    
    /// The animation duration of each frame, default is 0.1.
    var minFrameDuration: Float { get }
    
    /// Number of preloaded frames, default is 10.
    var preloadFrameCount: Int { get }
    
    /// Maximum number of repetitions of animation.
    var maxRepeatCount: Int { get }
    
    /// Decode image in background, default is true.
    var backgroundDecode: Bool { get }
    
}

public extension DanmakuGifCellModel {
    
    var minFrameDuration: Float {
        return 0.1
    }
    
    var preloadFrameCount: Int {
        return 10
    }
    
    var maxRepeatCount: Int {
        return .max
    }
    
    var backgroundDecode: Bool {
        return true
    }
    
}
