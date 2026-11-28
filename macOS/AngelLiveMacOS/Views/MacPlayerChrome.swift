import AngelLiveCore
import AppKit
import AVKit
internal import AVFoundation
import SwiftUI
#if canImport(KSPlayer)
import KSPlayer
#endif

enum MacPlayerChrome {
    static let inset: CGFloat = 16
    static let controlSize: CGFloat = 44
    static let symbolFont: Font = .system(size: 18, weight: .semibold)
    static let topControlSpacing: CGFloat = 12
    static let titleWidthFraction: CGFloat = 0.40
    static let titleHorizontalPadding: CGFloat = 16
    static let hoverSpace = "MacPlayerChrome.hoverSpace"

    static func isPointerOverControls(_ point: CGPoint, inset: CGFloat, bottomFrame: CGRect) -> Bool {
        (0..<(inset + controlSize)).contains(point.y) || bottomFrame.contains(point)
    }

    static func visibilityAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.30)
    }
}

extension EnvironmentValues {
    @Entry var macPlayerAcceptsCommands = true
}

extension View {
    func macPlayerGlass(in shape: some Shape, interactive: Bool = true) -> some View {
        modifier(MacPlayerGlassModifier(glassShape: shape, interactive: interactive))
    }

    func macPlayerTitleCapsule(
        hasSubtitle: Bool = false,
        interactive: Bool = false
    ) -> some View {
        let shape = hasSubtitle
            ? AnyShape(RoundedRectangle(cornerRadius: MacPlayerChrome.controlSize / 2))
            : AnyShape(Capsule())
        return padding(.horizontal, MacPlayerChrome.titleHorizontalPadding)
            .padding(.vertical, 6)
            .frame(minHeight: MacPlayerChrome.controlSize, alignment: .leading)
            .contentShape(shape)
            .macPlayerGlass(in: shape, interactive: interactive)
    }

    func macPlayerMediaText() -> some View {
        shadow(color: .black.opacity(0.85), radius: 3, y: 1)
    }
}

private struct MacPlayerGlassModifier<GlassShape: Shape>: ViewModifier {
    let glassShape: GlassShape
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let glass = Glass.regular.tint(.black.opacity(0.45)).interactive(interactive)
            content.glassEffect(glass, in: glassShape)
        } else {
            content.background(.ultraThinMaterial, in: glassShape)
        }
    }
}

struct MacPlayerGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0, content: content)
            .macPlayerGlass(in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

struct MacPlayerDanmakuStatus: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: DanmakuConnectionStatus?
    let controlsVisible: Bool
    var controlBottomInset: CGFloat = 0

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let status {
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .macPlayerGlass(in: Capsule(), interactive: false)
                    .padding(.bottom, controlsVisible ? 52 + controlBottomInset : 24)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.30), value: status)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

struct MacPlayerCommandActions {
    let isPlaying: Bool
    let isMuted: Bool
    let isFullscreen: Bool
    let togglePlayback: () -> Void
    let toggleMute: () -> Void
    let toggleFullscreen: () -> Void
    let changeVolume: (Float) -> Void
    let seek: ((Double) -> Void)?
    let escape: () -> Void
    let canControlPlayback: Bool
}

extension FocusedValues {
    @Entry var macPlayerCommands: MacPlayerCommandActions?
}

struct MacPlayerCommands: Commands {
    @FocusedValue(\.macPlayerCommands) private var player

    var body: some Commands {
        if let player {
            CommandMenu("播放") {
                if player.canControlPlayback {
                    Button(player.isPlaying ? "暂停" : "播放", action: player.togglePlayback)
                        .keyboardShortcut(.space, modifiers: [])
                    if let seek = player.seek {
                        Button("快退 5 秒") { seek(-5) }.keyboardShortcut(.leftArrow, modifiers: [])
                        Button("快进 5 秒") { seek(5) }.keyboardShortcut(.rightArrow, modifiers: [])
                        Button("快退 15 秒") { seek(-15) }.keyboardShortcut(.leftArrow, modifiers: .shift)
                        Button("快进 15 秒") { seek(15) }.keyboardShortcut(.rightArrow, modifiers: .shift)
                    }
                    Divider()
                    Button("调高音量") { player.changeVolume(0.05) }.keyboardShortcut(.upArrow, modifiers: [])
                    Button("调低音量") { player.changeVolume(-0.05) }.keyboardShortcut(.downArrow, modifiers: [])
                    Button(player.isMuted ? "取消静音" : "静音", action: player.toggleMute)
                        .keyboardShortcut("m", modifiers: [])
                    Divider()
                    Button(player.isFullscreen ? "退出全屏" : "进入全屏", action: player.toggleFullscreen)
                        .keyboardShortcut("f", modifiers: [])
                }
                Button("返回或关闭", action: player.escape)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}

extension View {
    func macPlayerEscapeKey(isEnabled: Bool, action: @escaping @MainActor () -> Void) -> some View {
        background {
            if isEnabled {
                MacPlayerEscapeKeyView(action: action)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    func macPlayerWindowState(_ window: NSWindow?, update: @escaping () -> Void) -> some View {
        onChange(of: window, initial: true) { update() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
                if $0.object as? NSWindow === window { update() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
                if $0.object as? NSWindow === window { update() }
            }
    }
}

private struct MacPlayerEscapeKeyView: NSViewRepresentable {
    let action: @MainActor () -> Void

    func makeNSView(context: Context) -> EscapeKeyView {
        EscapeKeyView(action: action)
    }

    func updateNSView(_ view: EscapeKeyView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: EscapeKeyView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class EscapeKeyView: NSView {
        var action: @MainActor () -> Void
        private var monitor: Any?

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            // A local monitor receives key-down even when the video surface has no SwiftUI focus.
            // AppKit menu-tracking events bypass the application's local monitors.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isKeyWindow, event.window === window,
                      window.attachedSheet == nil, NSApp.modalWindow == nil,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      event.charactersIgnoringModifiers == String(KeyEquivalent.escape.character)
                else { return event }

                if !event.isARepeat { self.action() }
                return nil
            }
        }

        func stopMonitoring() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        isolated deinit { stopMonitoring() }
    }
}

func macPlayerIcon(_ symbol: String, color: Color = .white) -> some View {
    Image(systemName: symbol)
        .font(MacPlayerChrome.symbolFont)
        .foregroundStyle(color)
        .frame(width: MacPlayerChrome.controlSize, height: MacPlayerChrome.controlSize)
        .contentShape(Rectangle())
}

func macPlayerText(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(minWidth: MacPlayerChrome.controlSize)
        .frame(height: MacPlayerChrome.controlSize)
        .contentShape(Rectangle())
}

struct MacPlayerCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            macPlayerIcon("xmark")
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .macPlayerGlass(in: Circle())
        .accessibilityLabel("关闭播放器")
        .help("关闭播放器")
    }
}

struct MacPlayerTitle: View {
    let title: String
    var subtitle: LocalizedStringResource? = nil
    let maximumWidth: CGFloat

    var body: some View {
        ViewThatFits(in: .horizontal) {
            labels.fixedSize(horizontal: true, vertical: false)
            labels
        }
        .macPlayerTitleCapsule(hasSubtitle: subtitle != nil)
        .accessibilityElement(children: .combine)
        .frame(maxWidth: maximumWidth, alignment: .leading)
        .allowsHitTesting(false)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Compact line boxes keep both lines and their padding within the 44-point chrome.
            Text(verbatim: title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 17)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 13)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

struct MacPlayerCenterPlayButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .macPlayerGlass(in: Circle())
        .accessibilityLabel(title)
    }
}

struct MacPlayerVolumeControl: View {
    @Binding var volume: Float
    let isMuted: Bool
    let sliderWidth: CGFloat
    let showsPercentage: Bool
    let toggleMute: () -> Void
    let onExpansionChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isHovered = false
    @State private var isEditing = false

    private var isExpanded: Bool { isHovered || isEditing || voiceOverEnabled }

    private var symbol: String {
        if isMuted { return "speaker.slash.fill" }
        if volume > 0.5 { return "speaker.wave.2.fill" }
        return volume > 0 ? "speaker.wave.1.fill" : "speaker.fill"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleMute) { macPlayerIcon(symbol) }
                .buttonStyle(.plain)
                .accessibilityLabel(isMuted ? "取消静音" : "静音")
                .help(isMuted ? "取消静音" : "静音")
            if isExpanded {
                HStack(spacing: 16) {
                    Slider(value: $volume, in: 0...1) { editing in
                        isEditing = editing
                    }
                    .controlSize(.small)
                    .tint(.white)
                    .frame(width: sliderWidth)
                    .accessibilityLabel("音量")
                    if showsPercentage {
                        Text(volume.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 36, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.trailing, 12)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onChange(of: isExpanded, initial: true) { onExpansionChanged(isExpanded) }
        .onDisappear { onExpansionChanged(false) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isExpanded)
    }
}

struct MacPlayerRateMenu: View {
    @Binding var rate: Float

    var body: some View {
        Menu {
            Picker("播放速度", selection: $rate) {
                ForEach([Float(0.75), 1, 1.25, 1.5, 2, 3], id: \.self) {
                    Text(rateLabel($0)).tag($0)
                }
            }
        } label: {
            macPlayerText(rateLabel(rate))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("播放速度，\(rateLabel(rate))"))
    }

    private func rateLabel(_ value: Float) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

struct MacPlayerSleepTimerMenu: View {
    @Binding var deadline: ContinuousClock.Instant?

    var body: some View {
        Menu {
            ForEach([10, 30, 60, 120], id: \.self) { minutes in
                Button("\(minutes) 分钟") { deadline = .now + .seconds(minutes * 60) }
            }
            if deadline != nil {
                Divider()
                Button("取消定时关闭") { deadline = nil }
            }
        } label: {
            Label("定时关闭", systemImage: "timer")
        }
    }
}

struct MacPlayerAirPlaySheet: View {
    let player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VStack(spacing: 12) {
                    Text("选择 AirPlay 设备以开始投屏。")
                        .foregroundStyle(.secondary)
                    MacPlayerAirPlayPicker(player: player)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("选择 AirPlay 设备")
                }
            } else {
                ContentUnavailableView("当前播放源暂不支持 AirPlay", systemImage: "airplayvideo",
                                       description: Text("请尝试切换其他线路或清晰度。"))
            }
        }
        .macSettingsPage("AirPlay 投屏")
        .macSettingsSheetPresentation()
        .frame(minWidth: 380, idealWidth: 420, minHeight: 240, idealHeight: 260)
    }
}

private struct MacPlayerAirPlayPicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateNSView(_ picker: AVRoutePickerView, context: Context) { picker.player = player }
}

#if canImport(KSPlayer)
struct MacPlayerSubtitlesMenu: View {
    let layer: KSPlayerLayer
    @ObservedObject private var subtitles: SubtitleModel

    init(layer: KSPlayerLayer) {
        self.layer = layer
        _subtitles = ObservedObject(wrappedValue: layer.subtitleModel)
    }

    var body: some View {
        if !subtitles.subtitleInfos.isEmpty {
            Menu {
                Picker("字幕", selection: Binding(
                    get: { subtitles.selectedSubtitleInfo?.subtitleID },
                    set: { id in layer.select(subtitleInfo: subtitles.subtitleInfos.first { $0.subtitleID == id }) }
                )) {
                    Text("关闭字幕").tag(nil as String?)
                    ForEach(subtitles.subtitleInfos, id: \.subtitleID) { subtitle in
                        Text(subtitle.name).tag(subtitle.subtitleID as String?)
                    }
                }
            } label: { macPlayerIcon("captions.bubble") }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .accessibilityLabel("字幕")
        }
    }
}
#endif
