import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

/// SharedAssets provides a centralized access point for shared resources
/// across iOS, macOS, and tvOS platforms.
public struct SharedAssets {

    /// Access to shared colors
    public struct Colors {
        /// App accent color with automatic dark mode support
        public static var appAccent: Color {
            Color("AppAccentColor", bundle: .module)
        }

        #if canImport(UIKit)
        /// App accent color as UIColor (iOS/tvOS)
        public static var appAccentUIColor: UIColor {
            UIColor(named: "AppAccentColor", in: .module, compatibleWith: nil) ?? .systemBlue
        }
        #elseif canImport(AppKit)
        /// App accent color as NSColor (macOS)
        public static var appAccentNSColor: NSColor {
            NSColor(named: "AppAccentColor", bundle: .module) ?? .systemBlue
        }
        #endif
    }

    /// Access to shared images
    public struct Images {
        // Add your image assets here
        // Example:
        // public static var logo: Image {
        //     Image("AppLogo", bundle: .module)
        // }

        #if canImport(UIKit)
        // public static var logoUIImage: UIImage? {
        //     UIImage(named: "AppLogo", in: .module, compatibleWith: nil)
        // }
        #elseif canImport(AppKit)
        // public static var logoNSImage: NSImage? {
        //     NSImage(named: "AppLogo")?.withSymbolConfiguration(.init(bundle: .module))
        // }
        #endif
    }
}

// MARK: - Convenience Extensions

#if canImport(SwiftUI)
extension Color {
    /// Initialize a color from the SharedAssets bundle
    public static func shared(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}

extension Image {
    /// Initialize an image from the SharedAssets bundle
    public static func shared(_ name: String) -> Image {
        Image(name, bundle: .module)
    }
}
#endif

// MARK: - Media browsing

@available(iOS 17, macOS 15, tvOS 17, *)
public struct MediaHeroStage<Artwork: View, Actions: View>: View {
    private let title: String
    private let metadata: String?
    private let tags: [String]
    private let synopsis: String?
    private let titleFont: Font
    private let height: CGFloat
    private let inset: CGFloat
    private let topClearance: CGFloat
    private let landscape: Bool
    private let fitsPoster: Bool
    private let artwork: Artwork
    private let actions: Actions

    public init(title: String, metadata: String? = nil, tags: [String] = [], synopsis: String?,
                titleFont: Font, height: CGFloat, inset: CGFloat, topClearance: CGFloat,
                landscape: Bool, fitsPoster: Bool = false,
                @ViewBuilder artwork: () -> Artwork, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.metadata = metadata
        self.tags = tags
        self.synopsis = synopsis
        self.titleFont = titleFont
        self.height = height
        self.inset = inset
        self.topClearance = topClearance
        self.landscape = landscape
        self.fitsPoster = fitsPoster
        self.artwork = artwork()
        self.actions = actions()
    }

    #if os(tvOS)
    private let heroTagFont = Font.system(size: 20, weight: .semibold)
    private let heroTagRadius: CGFloat = 6
    private let metadataFont = Font.subheadline.weight(.semibold)
    private let synopsisFont = Font.subheadline
    private let stackSpacing: CGFloat = 10
    #elseif os(macOS)
    // macOS text styles are 2–4 pt smaller than iOS; use the Mac reading sizes (13 pt body).
    private let heroTagFont = Font.system(size: 11, weight: .semibold)
    private let heroTagRadius: CGFloat = 4
    private let metadataFont = Font.system(size: 13, weight: .semibold)
    private let synopsisFont = Font.system(size: 13)
    private let stackSpacing: CGFloat = 0
    #else
    private let heroTagFont = Font.caption.weight(.semibold)
    private let heroTagRadius: CGFloat = 5
    private let metadataFont = Font.subheadline.weight(.semibold)
    private let synopsisFont = Font.subheadline
    private let stackSpacing: CGFloat = 10
    #endif

    public var body: some View {
        VStack(alignment: .leading, spacing: stackSpacing) {
            Text(verbatim: title)
                #if os(macOS)
                .font(.system(size: 32, weight: .bold))
                #else
                .font(titleFont)
                #endif
                .accessibilityAddTraits(.isHeader)
            if let metadata {
                Text(verbatim: metadata)
                    .font(metadataFont).foregroundStyle(.white.opacity(0.85))
                    #if os(macOS)
                    .padding(.top, 8)
                    #endif
            }
            if !tags.isEmpty {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(verbatim: tag)
                            .font(heroTagFont)
                            #if os(macOS)
                            .padding(.horizontal, 7).padding(.vertical, 2.5)
                            #else
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            #endif
                            .background(.white.opacity(0.16), in: .rect(cornerRadius: heroTagRadius))
                    }
                }
                #if os(macOS)
                .padding(.top, 10)
                #endif
            }
            if let synopsis, !synopsis.isEmpty {
                Text(verbatim: synopsis)
                    .font(synopsisFont)
                    #if os(macOS)
                    .lineSpacing(4)
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(.top, 10)
                    #else
                    .lineSpacing(3)
                    #endif
                    .lineLimit(3).foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if os(macOS)
            actions.padding(.top, 16)
            #else
            actions.padding(.top, 4)
            #endif
        }
        #if os(tvOS)
        .frame(maxWidth: 720, alignment: .leading)
        #else
        .frame(maxWidth: 540, alignment: .leading)
        #endif
        .foregroundStyle(.white)
        .padding(.horizontal, inset)
        .padding(.top, topClearance)
        #if os(macOS)
        .padding(.bottom, 24)
        #else
        .padding(.bottom, inset / 2)
        #endif
        .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Color.black
                    artwork
                        .frame(width: fitsPoster ? min(geometry.size.width, geometry.size.height * 2 / 3) : geometry.size.width,
                               height: geometry.size.height)
                        .clipped()
                    if landscape {
                        LinearGradient(colors: [.black.opacity(0.62), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.58, y: 0.5))
                    }
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.22), location: 0),
                        .init(color: .clear, location: 0.24),
                        .init(color: .black.opacity(0.18), location: 0.50),
                        .init(color: .black.opacity(0.46), location: 0.68),
                        .init(color: .black.opacity(0.78), location: 0.84),
                        .init(color: .black, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }
}

@available(iOS 17, macOS 15, tvOS 17, *)
public struct MediaCardLabel<Artwork: View>: View {
    private let title: String
    private let episodeNumber: Int
    private let synopsis: String?
    private let duration: String?
    private let completed: Bool
    private let lastWatched: Bool
    private let progress: Double?
    private let compact: Bool
    private let focused: Bool
    private let artwork: Artwork
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, episodeNumber: Int, synopsis: String?, duration: String? = nil,
                completed: Bool = false, lastWatched: Bool = false, progress: Double? = nil,
                compact: Bool = false, focused: Bool = false, @ViewBuilder artwork: () -> Artwork) {
        self.title = title
        self.episodeNumber = episodeNumber
        self.synopsis = synopsis
        self.duration = duration
        self.completed = completed
        self.lastWatched = lastWatched
        self.progress = progress
        self.compact = compact
        self.focused = focused
        self.artwork = artwork()
    }

    private var ordinal: String { "第 \(episodeNumber) 集" }
    #if os(tvOS)
    private let metadataFont = Font.system(size: 18)
    private let titleFont = Font.system(size: 25, weight: .bold)
    private let synopsisFont = Font.system(size: 20)
    #elseif os(macOS)
    private let metadataFont = Font.system(size: 11)
    private let titleFont = Font.system(size: 15, weight: .bold)
    private let synopsisFont = Font.system(size: 12)
    #else
    private let metadataFont = Font.caption2
    private let titleFont = Font.callout.bold()
    private let synopsisFont = Font.footnote
    #endif

    public var body: some View {
        Group {
            if compact {
                HStack(spacing: 12) {
                    still.frame(width: 136, height: 76)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: title.isEmpty ? ordinal : "\(ordinal) · \(title)")
                            #if os(macOS)
                            .font(.system(size: 13, weight: .semibold))
                            #else
                            .font(.subheadline.weight(.semibold))
                            #endif
                            .lineLimit(1)
                        synopsisText
                    }
                    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 0.5)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: mediaSynopsisSpacing) {
                    still
                    synopsisText.padding(.horizontal, 2)
                        .offset(y: focused && !reduceMotion ? 4 : 0)
                }
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: hovered)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: focused)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var synopsisText: some View {
        if let synopsis, !synopsis.isEmpty {
            Text(verbatim: synopsis)
                #if os(macOS)
                .font(synopsisFont)
                #else
                .font(compact ? .caption : synopsisFont)
                #endif
                .lineSpacing(2)
                #if os(tvOS)
                .foregroundStyle(.white.opacity(focused ? 0.86 : 0.54))
                #else
                .foregroundStyle(.white.opacity(hovered ? 0.84 : 0.62))
                #endif
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var still: some View {
        return Color.black.aspectRatio(16.0 / 9, contentMode: .fit)
            .overlay { artwork }
            .overlay { stillGradient }
            .overlay(alignment: .topLeading) {
                if completed || lastWatched {
                    MediaBadge(text: completed ? "已看完" : "上次观看",
                               symbol: completed ? "checkmark" : "circle.fill")
                        .padding(compact ? 6 : 10)
                }
            }
            .overlay {
                if hovered && !compact {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.18)) }
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if !compact && !title.isEmpty {
                            Text(verbatim: ordinal).fontWeight(.semibold)
                        }
                        Spacer(minLength: 0)
                        if let duration { Text(verbatim: duration).monospacedDigit() }
                    }
                    .font(metadataFont).foregroundStyle(.white.opacity(0.78))
                    if !compact {
                        Text(verbatim: title.isEmpty ? ordinal : title)
                            .font(titleFont).lineLimit(1)
                            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    }
                    if let progress, !completed, progress > 0, progress < 1 {
                        Capsule().fill(.white.opacity(0.24))
                            .overlay(alignment: .leading) {
                                GeometryReader { geometry in
                                    Capsule().fill(.white).frame(width: geometry.size.width * progress)
                                }
                            }
                            .frame(height: 3)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .padding(compact ? 7 : 12)
            }
            .modifier(MediaStillFrame(radius: compact ? 10 : 14, focused: focused, hovered: hovered && !compact))
    }
}

private var mediaSynopsisSpacing: CGFloat {
    #if os(tvOS)
    14
    #elseif os(macOS)
    8
    #else
    10
    #endif
}

private struct MediaStillFrame: ViewModifier {
    let radius: CGFloat
    let focused: Bool
    let hovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let border = LinearGradient(colors: [.white.opacity(focused ? 0.38 : hovered ? 0.30 : 0.20), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom)
        content.clipShape(shape)
            .overlay { shape.strokeBorder(border, lineWidth: 0.75) }
            .shadow(color: .white.opacity(focused ? 0.14 : hovered ? 0.08 : 0), radius: 8)
            .scaleEffect(reduceMotion ? 1 : focused ? 1.05 : hovered ? 1.02 : 1)
    }
}

public struct MediaArtworkPlaceholder: View {
    private let symbol: String
    public init(symbol: String = "film") { self.symbol = symbol }

    public var body: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [Color(white: 0.14), Color(white: 0.05)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
                .overlay {
                    RadialGradient(colors: [Color(red: 0.24, green: 0.29, blue: 0.36).opacity(0.22), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: geometry.size.width)
                }
                .overlay {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: geometry.size.height * 0.26, weight: .light))
                        .foregroundStyle(.white.opacity(0.55))
                }
        }
        .accessibilityHidden(true)
    }
}

private var stillGradient: LinearGradient {
    LinearGradient(stops: [
        .init(color: .clear, location: 0.38),
        .init(color: .black.opacity(0.10), location: 0.54),
        .init(color: .black.opacity(0.28), location: 0.68),
        .init(color: .black.opacity(0.50), location: 0.80),
        .init(color: .black.opacity(0.68), location: 0.90),
        .init(color: .black.opacity(0.84), location: 1)
    ], startPoint: .top, endPoint: .bottom)
}

@available(iOS 17, macOS 15, tvOS 17, *)
private struct MediaBadge: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if symbol == "circle.fill" {
                Circle().fill(.white).frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            } else if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
        }
        #if os(tvOS)
        .font(.system(size: 16, weight: .semibold))
        #elseif os(macOS)
        .font(.system(size: 11, weight: .semibold))
        #else
        .font(.caption2.weight(.semibold))
        #endif
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(.black.opacity(0.52), in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.75) }
    }
}

@available(iOS 17, macOS 15, tvOS 17, *)
public struct MediaUpNextCard<Artwork: View, Actions: View>: View {
    let episodeTitle: String
    let countdown: Int
    let artwork: Artwork
    let actions: Actions

    public init(episodeTitle: String, countdown: Int, @ViewBuilder artwork: () -> Artwork,
                @ViewBuilder actions: () -> Actions) {
        self.episodeTitle = episodeTitle
        self.countdown = countdown
        self.artwork = artwork()
        self.actions = actions()
    }

    #if os(tvOS)
    private let width: CGFloat = 208
    private let spacing: CGFloat = 20
    #elseif os(macOS)
    private let width: CGFloat = 132
    private let spacing: CGFloat = 12
    #else
    private let width: CGFloat = 104
    private let spacing: CGFloat = 10
    #endif

    public var body: some View {
        HStack(spacing: spacing) {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            artwork.frame(width: width, height: (width * 9 / 16).rounded(.down))
                .clipShape(shape)
                .overlay { shape.strokeBorder(.white.opacity(0.24), lineWidth: 0.75) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("下一集 · \(countdown) 秒后自动播放")
                    #if os(macOS)
                    .font(.system(size: 12).monospacedDigit())
                    #else
                    .font(.caption.monospacedDigit())
                    #endif
                    .foregroundStyle(.white.opacity(0.75))
                Text(verbatim: episodeTitle)
                    #if os(macOS)
                    .font(.system(size: 15, weight: .bold))
                    #else
                    .font(.headline.bold())
                    #endif
                    .lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { actions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { actions }
                }
                .padding(.top, 2)
            }
            .foregroundStyle(.white)
        }
        .padding(spacing)
        .accessibilityElement(children: .contain)
    }
}

@available(iOS 17, macOS 15, tvOS 17, *)
public struct MediaUpNextButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(primary: Bool) { self.primary = primary }

    public func makeBody(configuration: Configuration) -> some View {
        let bright = primary || focused
        configuration.label
            #if os(macOS)
            .font(.system(size: 13, weight: .semibold))
            #else
            .font(.subheadline.weight(.semibold))
            #endif
            .foregroundStyle(bright ? Color.black : .white)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            #if os(macOS)
            .padding(.horizontal, 14).frame(height: 28)
            #else
            .padding(.horizontal, 12).padding(.vertical, 6)
            #endif
            .background(.white.opacity(bright ? 1 : 0.10), in: Capsule())
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
            .shadow(color: .white.opacity(focused ? 0.25 : 0), radius: 7)
    }
}

#if DEBUG
@available(iOS 17, macOS 15, tvOS 17, *)
public struct MediaShowcase<Item: Hashable>: View {
    private let items: [Item]
    private let featured: Item
    private let title: KeyPath<Item, String>
    private let category: KeyPath<Item, String>
    private let synopsis: KeyPath<Item, String>
    private let artwork: KeyPath<Item, CGImage?>
    private let focus: FocusState<Item?>.Binding?
    private let open: (Item) -> Void

    public init(items: [Item], featured: Item, title: KeyPath<Item, String>, category: KeyPath<Item, String>,
                synopsis: KeyPath<Item, String>, artwork: KeyPath<Item, CGImage?>,
                focus: FocusState<Item?>.Binding? = nil, open: @escaping (Item) -> Void) {
        self.items = items
        self.featured = featured
        self.title = title
        self.category = category
        self.synopsis = synopsis
        self.artwork = artwork
        self.focus = focus
        self.open = open
    }

    public var body: some View {
        GeometryReader { geometry in
            #if os(tvOS)
            let inset: CGFloat = 70
            let topClearance = inset + 56
            let spacing: CGFloat = 36
            #elseif os(macOS)
            let inset: CGFloat = geometry.size.width >= 960 ? 40 : geometry.size.width >= 720 ? 32 : 24
            let topClearance = geometry.safeAreaInsets.top + inset
            let spacing: CGFloat = 20
            #else
            let inset: CGFloat = geometry.size.width >= 720 ? 32 : 20
            let spacing: CGFloat = 18
            let topClearance = geometry.safeAreaInsets.top + inset
            #endif
            let railWidth = max(0, geometry.size.width - 2 * inset)
            let cardWidth = geometry.size.width >= 720 ? (railWidth - 2 * spacing) / 3 : min(railWidth, 260)
            ScrollView(showsIndicators: false) {
                #if os(macOS)
                let sectionSpacing: CGFloat = 14
                #else
                let sectionSpacing: CGFloat = 18
                #endif
                VStack(alignment: .leading, spacing: sectionSpacing) {
                    MediaHeroStage(title: featured[keyPath: title], synopsis: featured[keyPath: synopsis],
                                   titleFont: .largeTitle.bold(), height: geometry.size.height * 0.52,
                                   inset: inset, topClearance: topClearance, landscape: true) {
                        image(for: featured)
                    } actions: {
                        Button { open(featured) } label: {
                            Text("查看详情")
                                #if os(macOS)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16).frame(height: 32)
                                .background(.white, in: Capsule())
                                #elseif !os(tvOS)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 22).frame(height: 44)
                                .background(.white, in: Capsule())
                                #endif
                                .foregroundStyle(.black)
                        }
                        #if os(tvOS)
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.white)
                        #else
                        .buttonStyle(.plain)
                        #endif
                        .accessibilityLabel("查看\(featured[keyPath: title])详情")
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif

                    Text("精选演示")
                        #if os(macOS)
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.top, 10)
                        #else
                        .font(.title3.bold())
                        #endif
                        .padding(.horizontal, inset)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: spacing) {
                            ForEach(items, id: \.self) { item in
                                let card = Button { open(item) } label: {
                                    poster(for: item).frame(width: cardWidth)
                                }
                                #if os(tvOS)
                                .buttonStyle(ShowcaseButtonStyle())
                                .focusEffectDisabled()
                                #else
                                .buttonStyle(.plain)
                                #endif
                                if let focus { card.focused(focus, equals: item) } else { card }
                            }
                        }
                        .padding(.horizontal, inset)
                    }
                    .scrollClipDisabled()
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
                .padding(.bottom, inset)
            }
            #if os(tvOS) || os(iOS) || os(macOS)
            .ignoresSafeArea(.container, edges: .top)
            #endif
        }
        #if os(tvOS)
        .ignoresSafeArea(.container, edges: .horizontal)
        #endif
        .foregroundStyle(.white)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func poster(for item: Item) -> some View {
        ShowcasePoster(title: item[keyPath: title], category: item[keyPath: category],
                       synopsis: item[keyPath: synopsis], image: image(for: item))
    }

    @ViewBuilder
    private func image(for item: Item) -> some View {
        if let image = item[keyPath: artwork] {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            MediaArtworkPlaceholder(symbol: "exclamationmark.triangle")
        }
    }
}

private struct ShowcaseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.84 : 1)
    }
}

@available(iOS 17, macOS 15, tvOS 17, *)
private struct ShowcasePoster<Artwork: View>: View {
    let title: String
    let category: String
    let synopsis: String
    let image: Artwork
    @State private var hovered = false
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: mediaSynopsisSpacing) {
            Color.black.aspectRatio(16.0 / 9, contentMode: .fit)
                .overlay { image }
                .overlay { stillGradient }
                .overlay(alignment: .topLeading) { MediaBadge(text: category).padding(12) }
                .overlay(alignment: .bottomLeading) {
                    Text(verbatim: title)
                        #if os(tvOS)
                        .font(.system(size: 30, weight: .bold))
                        #else
                        .font(.title3.bold())
                        #endif
                        .lineLimit(1).padding(14)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
                .modifier(MediaStillFrame(radius: 14, focused: focused, hovered: hovered))
            Text(verbatim: synopsis)
                #if os(tvOS)
                .font(.system(size: 20)).foregroundStyle(.white.opacity(focused ? 0.86 : 0.54))
                #elseif os(macOS)
                .font(.system(size: 12)).foregroundStyle(.white.opacity(hovered ? 0.84 : 0.62))
                #else
                .font(.footnote).foregroundStyle(.white.opacity(hovered ? 0.84 : 0.62))
                #endif
                .lineLimit(2, reservesSpace: true).lineSpacing(2)
                .offset(y: focused && !reduceMotion ? 4 : 0)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: hovered)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: focused)
        .accessibilityElement(children: .combine)
    }
}
#endif
