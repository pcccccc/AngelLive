import SwiftUI

public struct PlatformAppearanceCard: View {
    private let pluginID: String
    private let title: String
    private let liveType: LiveType
    private let appearance: PlatformCardAppearanceOverride
    private let backgroundStyle: PlatformBackgroundStyle
    private let defaultBackground: Image
    private let idiom: PlatformDeviceIdiom
    private let radius: CGFloat
    private let blur: Double
    private let scrim: Bool
    private let catalogRevision: UInt
    private let isFocused: Bool
    @Environment(\.platformAppearanceLibrary) private var library

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var smallTitleHeight = 19.0
    @ScaledMetric(relativeTo: .headline) private var tvTitleHeight = 38.0
    @State private var artwork: PlatformAppearanceArtwork?
    @State private var loadedLogo: LoadedImage?
    @State private var loadedBackground: LoadedImage?

    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    private var logoImage: CGImage? { loadedLogo?.id == appearance.logoMode.assetID ? loadedLogo?.image : nil }

    private var backgroundImage: CGImage? {
        loadedBackground?.id == backgroundStyle.assetID ? loadedBackground?.image : nil
    }

    private var wordmark: CGImage? {
        switch appearance.logoMode {
        case .auto: artwork?.wordmark
        case .customImage where logoImage == nil: artwork?.wordmark
        default: nil
        }
    }

    private var showsTitle: Bool {
        appearance.titleVisibility == .always || (appearance.titleVisibility == .auto && wordmark == nil)
    }

    public init(
        pluginID: String,
        title: String,
        liveType: LiveType,
        appearance: PlatformCardAppearanceOverride,
        snapshot: PlatformAppearanceSnapshot,
        idiom: PlatformDeviceIdiom,
        defaultBackground: Image,
        catalogRevision: UInt = 0,
        isFocused: Bool = false
    ) {
        self.pluginID = pluginID
        self.title = title
        self.liveType = liveType
        self.appearance = appearance
        backgroundStyle = appearance.backgroundOverride ?? snapshot.globalBackground
        self.defaultBackground = defaultBackground
        self.idiom = idiom
        radius = snapshot.cardCornerRadius(for: idiom)
        blur = snapshot.backgroundBlurRadius
        scrim = snapshot.contrastScrimEnabled
        self.catalogRevision = catalogRevision
        self.isFocused = isFocused
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                PlatformAppearanceBackdrop(
                    style: backgroundStyle,
                    image: backgroundImage,
                    defaultBackground: defaultBackground,
                    aura: artwork?.dominantColor ?? neutralAura,
                    size: size,
                    blur: blur,
                    scrim: scrim
                )
                .blur(radius: isFocused ? 8 : 0)

                foreground(in: size)
                    .opacity(idiom == .tv && isFocused ? 0 : 1)
            }
            .frame(width: size.width, height: size.height)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(shape)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isFocused)
        .accessibilityHidden(true)
        .task(
            id: ArtworkRequest(
                dark: usesLightArtwork,
                revision: catalogRevision,
                liveType: liveType
            )
        ) {
            let result = await (library?.artwork ?? .shared)
                .artwork(
                    pluginID: pluginID,
                    liveType: liveType,
                    dark: colorScheme == .dark,
                    revision: catalogRevision,
                    includesWordmark: true
                )
            if !Task.isCancelled { artwork = result }
        }
        .task(id: AssetRequest(id: appearance.logoMode.assetID, revision: store.assetsRevision)) {
            let image = await load(appearance.logoMode.assetID)
            if !Task.isCancelled { loadedLogo = image }
        }
        .task(id: AssetRequest(id: backgroundStyle.assetID, revision: store.assetsRevision)) {
            let image = await load(backgroundStyle.assetID)
            if !Task.isCancelled { loadedBackground = image }
        }
    }

    // MARK: - Card Content

    private func foreground(in size: CGSize) -> some View {
        let inset = min(idiom == .tv ? 20 : 12, size.height * 0.12)
        let width = max(1, size.width - 2 * inset)
        let height = max(1, size.height - 2 * inset)
        let titleHeight = showsTitle ? min(idiom == .tv ? tvTitleHeight : smallTitleHeight, height * 0.45) : 0
        let spacing = showsTitle ? min(idiom == .tv ? 14 : 8, height * 0.12) : 0
        let markHeight = max(1, height - titleHeight - spacing)
        let side = min(
            idiom == .tv ? 86 : 52,
            markHeight,
            width
        )

        let sideInset = (size.width - side) / 2
        let topInset = (size.height - side - titleHeight - spacing) / 2
        let cornerInset = max(sideInset, topInset)
        let badgeRadius = cornerInset < radius ? min(side * 0.24, max(8, radius - cornerInset)) : side * 0.24

        return VStack(spacing: spacing) {
            if let wordmark {
                Image(decorative: wordmark, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        maxWidth: min(width * 0.92, idiom == .tv ? 318 : 180),
                        maxHeight: showsTitle ? side : min(markHeight, idiom == .tv ? 130 : 78)
                    )
                    .frame(height: showsTitle ? side : nil)
            } else {
                PlatformAppearanceIcon(
                    pluginID: pluginID,
                    title: title,
                    mode: appearance.logoMode,
                    customImage: logoImage,
                    square: artwork?.square,
                    side: side,
                    radius: badgeRadius
                )
            }

            if showsTitle {
                Text(verbatim: title)
                    .font(idiom == .tv ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(prefersWhiteTitle ? Color.white : .primary)
                    .lineLimit(1)
                    .frame(width: width, height: titleHeight)
                    .shadow(
                        color: prefersWhiteTitle ? .black.opacity(0.4) : .clear,
                        radius: 2,
                        y: 1
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var neutralAura: PlatformRGBAColor {
        let rgb = PluginManagementMonogramStyle(pluginID: pluginID, displayName: title).backgroundRGB
        return .init(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue
        )
    }

    private var usesLightArtwork: Bool { colorScheme == .dark || prefersWhiteTitle }

    private var prefersWhiteTitle: Bool {
        switch backgroundStyle {
        case .preset: true
        case .customImage: backgroundImage != nil && scrim
        default: false
        }
    }

    private func load(_ id: String?) async -> LoadedImage? {
        guard let id, let image = await (library?.assets ?? .shared).image(for: id) else { return nil }
        return LoadedImage(id: id, image: image)
    }
}

// MARK: - Artwork

struct ArtworkRequest: Equatable {
    let dark: Bool
    let revision: UInt
    let liveType: LiveType
}

struct AssetRequest: Equatable {
    let id: String?
    let revision: Int
}

private struct LoadedImage {
    let id: String
    let image: CGImage
}

extension PlatformRGBAColor {
    var swiftUIColor: Color {
        Color(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: alpha
        )
    }
}

struct PlatformAppearanceBackdrop: View {
    let style: PlatformBackgroundStyle
    let image: CGImage?
    let defaultBackground: Image
    let aura: PlatformRGBAColor
    let size: CGSize
    let blur: Double
    let scrim: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch style {
        case .defaultAsset:
            defaultImage
        case .dominantIconAura:
            let color = aura.swiftUIColor
            Rectangle()
                .fill(.background.secondary)
                .overlay {
                    LinearGradient(
                        colors: [
                            color.opacity(colorScheme == .dark ? 0.24 : 0.14),
                            color.opacity(colorScheme == .dark ? 0.08 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        case .systemSurface:
            Rectangle()
                .fill(.background.secondary)
        case .preset(let preset):
            let colors = preset.colors
            LinearGradient(
                colors: [colors.0.swiftUIColor, colors.1.swiftUIColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .customImage(_, let focalY):
            if let image {
                customImage(image, focalY: focalY)
            } else {
                defaultImage
            }
        }
    }

    private var defaultImage: some View {
        defaultBackground.resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    private func customImage(_ image: CGImage, focalY: Double) -> some View {
        let fill = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let imageHeight = CGFloat(image.height) * fill
        let grow = 1 + 2 * blur / max(1, min(size.width, size.height))
        return Rectangle()
            .fill(.background)
            .overlay {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: CGFloat(image.width) * fill, height: imageHeight)
                    .offset(y: (0.5 - focalY) * (imageHeight - size.height))
                    .scaleEffect(grow)
                    .blur(radius: blur)
            }
            .overlay {
                if scrim {
                    LinearGradient(
                        colors: [.black.opacity(0.13), .black.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipped()
    }
}
