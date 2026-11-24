#if canImport(KSPlayer)
import AVFAudio
import MediaPlayer
import SwiftUI
import UIKit

struct VodPlayerGestures: View {
    let isEnabled: Bool
    let allowsSeek: Bool
    let allowsAdjustments: Bool
    let allowsBoost: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onSeek: (CGSize) -> Void
    let onSeekEnd: (Bool) -> Void
    let onBoost: (Bool) -> Void
    let onAdjustment: (Adjustment) -> Void

    @Environment(\.fullUIWindowContext) private var windowContext
    @State private var systemVolume = MPVolumeView()
    @State private var volumeObserver = VolumeButtonObserver()
    @State private var drag: Drag?
    @State private var boosting = false
    @GestureState private var hasDrag = false

    enum Adjustment {
        case brightness(Double)
        case volume(Double)

        var value: Double {
            switch self {
            case .brightness(let value), .volume(let value): value
            }
        }

        var icon: String {
            switch self {
            case .brightness: "sun.max.fill"
            case .volume: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill"
            }
        }

        var title: String {
            switch self {
            case .brightness: "亮度"
            case .volume: "音量"
            }
        }
    }

    private enum Drag {
        case seek
        case brightness(CGFloat)
        case volume(Float)
        case ignored
    }

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(.rect)
                .gesture(
                    TapGesture(count: 2).exclusively(before: TapGesture(count: 1))
                        .onEnded { result in
                            guard isEnabled, !boosting else { return }
                            switch result {
                            case .first: onDoubleTap()
                            case .second: onTap()
                            }
                        }
                )
                .simultaneousGesture(pan(size: geometry.size))
                .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 12) {
                    guard isEnabled, allowsBoost, drag == nil else { return }
                    boosting = true
                    onBoost(true)
                } onPressingChanged: { pressing in
                    if !pressing { endBoost() }
                }
                .onChange(of: hasDrag) { _, active in
                    if !active { endDrag(cancelled: true) }
                }
        }
        .allowsHitTesting(isEnabled)
        .accessibilityHidden(true)
        .background(alignment: .topLeading) {
            if allowsAdjustments {
                VolumeViewWrapper(volumeView: systemVolume)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: isEnabled && allowsAdjustments, initial: true) { _, listening in
            if listening {
                let action = onAdjustment
                volumeObserver.onChange = { value in action(.volume(Double(value))) }
                volumeObserver.start()
            } else {
                stopObservingVolume()
            }
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                endDrag(cancelled: true)
                endBoost()
            }
        }
        .onChange(of: allowsBoost) { _, enabled in
            if !enabled { endBoost() }
        }
        .onDisappear {
            stopObservingVolume()
            endDrag(cancelled: true)
            endBoost()
        }
    }

    private func pan(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($hasDrag) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard isEnabled, !boosting else { return }
                if drag == nil {
                    let x = abs(value.translation.width)
                    let y = abs(value.translation.height)
                    if x > y * 1.2, allowsSeek {
                        drag = .seek
                    } else if y > x * 1.2, allowsAdjustments, size.height > 0 {
                        if value.startLocation.x < size.width / 2, let screen = windowContext?.window?.windowScene?.screen {
                            drag = .brightness(screen.brightness)
                        } else if value.startLocation.x >= size.width / 2 {
                            drag = .volume(AVAudioSession.sharedInstance().outputVolume)
                        }
                    } else if max(x, y) >= 24 {
                        drag = .ignored
                    }
                }
                switch drag {
                case .seek:
                    onSeek(value.translation)
                case .brightness(let initial):
                    let brightness = min(max(initial - value.translation.height / size.height, 0), 1)
                    windowContext?.window?.windowScene?.screen.brightness = brightness
                    onAdjustment(.brightness(Double(brightness)))
                case .volume(let initial):
                    let volume = min(max(initial - Float(value.translation.height / size.height), 0), 1)
                    if let slider = systemVolume.subviews.compactMap({ $0 as? UISlider }).first {
                        slider.setValue(volume, animated: false)
                        slider.sendActions(for: .valueChanged)
                    }
                    onAdjustment(.volume(Double(volume)))
                case .ignored, nil:
                    break
                }
            }
            .onEnded { value in
                if case .seek = drag { onSeek(value.translation) }
                endDrag(cancelled: value.translation.height < -48)
            }
    }

    private func endDrag(cancelled: Bool) {
        let ended = drag
        drag = nil
        if case .seek = ended { onSeekEnd(cancelled) }
    }

    private func endBoost() {
        guard boosting else { return }
        boosting = false
        onBoost(false)
    }

    private func stopObservingVolume() {
        volumeObserver.stop()
        volumeObserver.onChange = nil
    }
}
#endif
