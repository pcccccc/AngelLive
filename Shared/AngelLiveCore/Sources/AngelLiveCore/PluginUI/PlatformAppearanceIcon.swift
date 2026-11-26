import Observation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PlatformAppearanceIcon: View {
    let pluginID: String
    let title: String
    let mode: PlatformLogoMode
    let customImage: CGImage?
    let square: CGImage?
    let side: CGFloat
    let radius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            switch mode {
            case .customImage where customImage != nil:
                if let customImage { bitmap(customImage) }
            case let .symbol(name, tintHex) where Self.hasSymbol(name):
                badge(
                    symbol: name,
                    text: nil,
                    tintHex: tintHex
                )
            case let .monogramBadge(text, tintHex):
                badge(
                    symbol: nil,
                    text: text,
                    tintHex: tintHex
                )
            default:
                if let square {
                    bitmap(square)
                } else {
                    badge(
                        symbol: nil,
                        text: nil,
                        tintHex: nil
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    // MARK: - Badge

    private func badge(
        symbol: String?,
        text: String?,
        tintHex: String?
    ) -> some View {
        let tint = tintHex.flatMap(PlatformRGBAColor.init(hex:))
        let dark = colorScheme == .dark
        let highlight = tint != nil ? 0.24 : (dark ? 0.20 : 0.70)

        return ZStack {
            if let tint {
                shape.fill(tint.swiftUIColor.gradient)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(.white.opacity(dark ? 0.14 : 0.76))
            }

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: side * 0.47, weight: .semibold))
            } else {
                Text(
                    verbatim: text
                        ?? PluginManagementMonogramStyle(pluginID: pluginID, displayName: title).glyph
                )
                .font(.system(size: side * 0.48, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.46)
                .padding(.horizontal, side * 0.08)
            }
        }
        .foregroundStyle(ink(for: tint))
        .frame(width: side, height: side)
        .overlay {
            shape.strokeBorder(.white.opacity(highlight), lineWidth: 1 / displayScale)
        }
        .shadow(
            color: .black.opacity(dark ? 0.12 : 0.08),
            radius: side * 0.07,
            y: side * 0.035
        )
    }

    private func ink(for tint: PlatformRGBAColor?) -> Color {
        guard let tint else { return .primary }
        let luminance = 0.2126 * tint.red + 0.7152 * tint.green + 0.0722 * tint.blue
        return luminance > 0.57 ? .black : .white
    }

    private func bitmap(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .clipShape(shape)
    }

    private static func hasSymbol(_ name: String) -> Bool {
        #if os(macOS)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        UIImage(systemName: name) != nil
        #endif
    }
}

#if !os(tvOS)
// MARK: - Management List

public struct PlatformAppearanceRowIcon: View {
    let platform: Platformdescription
    let side: CGFloat

    @Environment(\.platformAppearanceLibrary) private var library
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PluginAvailabilityService.self) private var catalog
    @State private var square: CGImage?
    @State private var customImage: CGImage?
    @State private var loadedAssetID: String?

    public init(platform: Platformdescription, side: CGFloat) {
        self.platform = platform
        self.side = side
    }

    public var body: some View {
        let store = library?.store ?? .shared
        let mode = store.snapshot.appearance(for: platform.pluginId).logoMode
        let artworkRequest = ArtworkRequest(
            dark: colorScheme == .dark,
            revision: catalog.catalogRevision,
            liveType: platform.liveType
        )

        PlatformAppearanceIcon(
            pluginID: platform.pluginId,
            title: platform.title,
            mode: mode,
            customImage: loadedAssetID == mode.assetID ? customImage : nil,
            square: square,
            side: side,
            radius: side / 4
        )
        .task(id: artworkRequest) {
            let artwork = await (library?.artwork ?? .shared).artwork(
                pluginID: platform.pluginId,
                liveType: platform.liveType,
                dark: artworkRequest.dark,
                revision: artworkRequest.revision,
                includesWordmark: false
            )
            if !Task.isCancelled { square = artwork.square }
        }
        .task(id: AssetRequest(id: mode.assetID, revision: store.assetsRevision)) {
            guard let id = mode.assetID else {
                loadedAssetID = nil
                customImage = nil
                return
            }
            let image = await (library?.assets ?? .shared).image(for: id)
            guard !Task.isCancelled else { return }
            customImage = image
            loadedAssetID = id
        }
    }
}

// MARK: - Sidebar

/// Builds actual image values for SwiftUI's system-owned Tab labels.
@MainActor
@Observable
public final class PlatformAppearanceSidebarIcons {
    public struct Request: Equatable {
        fileprivate let platforms: [Platformdescription]
        fileprivate let logos: [String: PlatformLogoMode]
        fileprivate let revision: UInt
        fileprivate let assetsRevision: Int
        fileprivate let dark: Bool
    }

    private var icons: [String: Entry] = [:]

    private struct Entry {
        let logo: PlatformLogoMode
        let title: String
        let image: Image
    }

    private let library: PlatformAppearanceLibrary?

    public init(library: PlatformAppearanceLibrary? = nil) {
        self.library = library
    }

    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    public func request(
        platforms: [Platformdescription],
        catalogRevision: UInt,
        dark: Bool
    ) -> Request {
        let logos = platforms.map { ($0.pluginId, store.snapshot.appearance(for: $0.pluginId).logoMode) }
        return .init(
            platforms: platforms,
            logos: Dictionary(logos, uniquingKeysWith: { first, _ in first }),
            revision: catalogRevision,
            assetsRevision: store.assetsRevision,
            dark: dark
        )
    }

    public func load(
        _ request: Request,
        side: CGFloat,
        displayScale: CGFloat
    ) async {
        var next: [String: Entry] = [:]
        for platform in request.platforms {
            let mode = request.logos[platform.pluginId] ?? .auto
            let artwork = await (library?.artwork ?? .shared).artwork(
                pluginID: platform.pluginId,
                liveType: platform.liveType,
                dark: request.dark,
                revision: request.revision,
                includesWordmark: false
            )
            let customImage: CGImage?
            if let id = mode.assetID {
                customImage = await (library?.assets ?? .shared).image(for: id)
            } else {
                customImage = nil
            }
            guard !Task.isCancelled else { return }
            let icon = PlatformAppearanceIcon(
                pluginID: platform.pluginId,
                title: platform.title,
                mode: mode,
                customImage: customImage,
                square: artwork.square,
                side: side,
                radius: side * 0.24
            )
            .environment(\.colorScheme, request.dark ? .dark : .light)
            if let image = render(icon, scale: displayScale) {
                next[platform.pluginId] = Entry(
                    logo: mode,
                    title: platform.title,
                    image: image
                )
            }
        }
        if !Task.isCancelled { icons = next }
    }

    public func image(
        for platform: Platformdescription,
        side: CGFloat,
        displayScale: CGFloat
    ) -> Image {
        let mode = store.snapshot.appearance(for: platform.pluginId).logoMode
        if let entry = icons[platform.pluginId], entry.logo == mode, entry.title == platform.title {
            return entry.image.renderingMode(.original)
        }
        let fallback = PlatformAppearanceIcon(
            pluginID: platform.pluginId,
            title: platform.title,
            mode: mode,
            customImage: nil,
            square: nil,
            side: side,
            radius: side * 0.24
        )
        return render(fallback, scale: displayScale)?.renderingMode(.original)
            ?? Image(systemName: "textformat")
    }

    private func render<V: View>(_ view: V, scale: CGFloat) -> Image? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = max(1, scale)
        #if os(macOS)
        return renderer.nsImage.map(Image.init(nsImage:))
        #else
        return renderer.uiImage.map(Image.init(uiImage:))
        #endif
    }
}
#endif
