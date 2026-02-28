//
//  PlayerKernelSupport.swift
//  AngelLive
//

import AngelLiveCore

enum PlayerKernelSupport {
    static var isVLCAvailable: Bool {
        #if canImport(VLCKitSPM) || canImport(VLCKit)
        true
        #else
        false
        #endif
    }

    static var isKSPlayerAvailable: Bool {
        #if canImport(KSPlayer)
        true
        #else
        false
        #endif
    }

    static var availableKernels: [PlayerKernel] {
        if isKSPlayerAvailable && isVLCAvailable {
            return [.ksplayer, .vlc4]
        }
        if isKSPlayerAvailable {
            return [.ksplayer]
        }
        if isVLCAvailable {
            return [.vlc4]
        }
        return []
    }

    static func resolvedKernel(for preferred: PlayerKernel) -> PlayerKernel {
        if !isKSPlayerAvailable && !isVLCAvailable {
            return .ksplayer
        }
        if preferred == .vlc4, !isVLCAvailable {
            return .ksplayer
        }
        if preferred == .ksplayer, !isKSPlayerAvailable {
            return .vlc4
        }
        return preferred
    }
}
