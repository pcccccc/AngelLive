#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

public enum PlatformAppearanceDemo {
    public static let isEnabled = ProcessInfo.processInfo.arguments.contains("--ui-test-platform-appearance")
        || ProcessInfo.processInfo.environment["ANGELLIVE_PLATFORM_APPEARANCE_DEMO"] == "1"

    @MainActor fileprivate static let session = Result { try Session() }

    @MainActor fileprivate struct Session {
        let library: PlatformAppearanceLibrary
        let platforms = PlatformViewModel()
        #if !os(tvOS)
        let sidebarIcons: PlatformAppearanceSidebarIcons
        #endif
        let availability: PluginAvailabilityService
        let defaults: UserDefaults

        init() throws {
            let id = UUID().uuidString
            let directory = URL.temporaryDirectory.appending(path: "PlatformAppearanceDemo").appending(path: id)
            let manager = try makeManager(in: directory)
            library = PlatformAppearanceLibrary(
                store: PlatformAppearanceStore(directory: directory, useHostDefaults: false, initialSnapshot: initialSnapshot),
                artwork: PlatformAppearanceArtworkLoader(storage: manager.storage),
                assets: PlatformAppearanceAssetCache(directory: directory.appending(path: "Assets"))
            )
            #if !os(tvOS)
            sidebarIcons = PlatformAppearanceSidebarIcons(library: library)
            #endif
            platforms.platformInfo = PlatformAppearanceDemo.platforms
            availability = PluginAvailabilityService(
                initialInstalledPluginIds: platforms.platformInfo.map(\.pluginId),
                pluginManager: { manager }
            )
            guard let suite = UserDefaults(suiteName: "dev.angellive.appearance-demo.\(id)") else {
                throw CocoaError(.fileWriteUnknown)
            }
            defaults = suite
        }
    }

    static let playlist = PlaylistInstance(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "自建片单", iconURL: nil, sourceURL: "https://playlist.example.invalid/demo.m3u")
    static let playlistDescription = "本地与订阅流媒体播放列表"

    public static var platforms: [Platformdescription] { [
        platform("fixture.wordmark", "综合演播", "高清综合演播与现场频道"),
        platform("fixture.aura", "赛事频道", "实时体育赛事与多视角信号"),
        platform("fixture.alpha", "纪实剧场", "全天候纪录片与人文专题轮播"),
        platform("fixture.beta", "午夜电台", "沉浸式音乐与夜间伴随音频"),
        platform(playlist.liveType.rawValue, playlist.name, playlistDescription)
    ] }

    static var initialSnapshot: PlatformAppearanceSnapshot {
        var snapshot = PlatformAppearanceSnapshot()
        snapshot.orderedPluginIds = platforms.map(\.pluginId)
        return snapshot
    }

    private static func platform(_ id: String, _ title: String, _ description: String) -> Platformdescription {
        Platformdescription(title: title, pluginId: id, bigPic: "", smallPic: "", descripiton: description,
                            liveType: LiveType(rawValue: id)!)
    }

    static func makeManager(in directory: URL) throws -> LiveParsePluginManager {
        let storage = try LiveParsePluginStorage(baseDirectory: directory.appending(path: "LiveParse"))
        for item in platforms where !PlaylistPlatformIdentity.isPlaylist(item.liveType) {
            let id = item.pluginId
            let root = storage.pluginVersionDirectory(pluginId: id, version: "1.0.0")
            let assets = root.appending(path: "assets", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            let manifest = LiveParsePluginManifest(pluginId: id, version: "1.0.0", apiVersion: 1,
                displayName: item.title, platformDescription: item.descripiton, liveTypes: [id], entry: "index.js")
            try JSONEncoder().encode(manifest).write(to: root.appending(path: "manifest.json"))
            try Data("globalThis.LiveParsePlugin = {apiVersion: 1}".utf8).write(to: root.appending(path: "index.js"))
            if id == "fixture.wordmark" {
                for dark in [false, true] {
                    let suffix = dark ? "_dark" : ""
                    try drawArtwork(at: assets.appending(path: "tv_\(id)_big\(suffix).png"),
                                    title: item.title, dark: dark)
                }
            } else if id == "fixture.aura" {
                try drawArtwork(at: assets.appending(path: "live_card_\(id).png"), title: nil, dark: false)
            }
        }
        return LiveParsePlugins.makeFixtureManager(storage: storage)
    }

    private static func drawArtwork(at url: URL, title: String?, dark: Bool) throws {
        let width = title == nil ? 144 : 416
        let height = title == nil ? 144 : 104
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.fileWriteUnknown) }
        if let title {
            let color = CGColor(gray: dark ? 0.98 : 0.13, alpha: 1)
            let attributes: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): CTFontCreateWithName("PingFangSC-Semibold" as CFString, 79, nil),
                .init(kCTKernAttributeName as String): 4,
                .init(kCTForegroundColorAttributeName as String): color
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: attributes))
            let ink = CTLineGetImageBounds(line, context)
            context.textPosition = CGPoint(x: CGFloat(width) / 2 - ink.midX, y: CGFloat(height) / 2 - ink.midY)
            CTLineDraw(line, context)
        } else {
            context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                                   cornerWidth: 30, cornerHeight: 30, transform: nil))
            context.clip()
            let colors = [
                CGColor(srgbRed: 200 / 255, green: 90 / 255, blue: 59 / 255, alpha: 1),
                CGColor(srgbRed: 168 / 255, green: 70 / 255, blue: 43 / 255, alpha: 1)
            ]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            ) else { throw CocoaError(.fileWriteUnknown) }
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 144), end: CGPoint(x: 144, y: 0), options: [])

            let play = CGMutablePath()
            play.move(to: CGPoint(x: 55, y: 44))
            play.addLine(to: CGPoint(x: 55, y: 100))
            play.addLine(to: CGPoint(x: 98, y: 72))
            play.closeSubpath()
            context.addPath(play)
            context.setLineJoin(.round)
            context.setLineWidth(6)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.drawPath(using: .fillStroke)
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

}

// MARK: - Isolated Window

public enum PlatformAppearanceDemoPage {
    case grid
    #if !os(tvOS)
    case card(Platformdescription)
    case settings
    #endif
}

public struct PlatformAppearanceDemoRoot<Content: View>: View {
    private let page: (PlatformAppearanceDemoPage, CGFloat) -> Content

    private enum TabID: Hashable {
        case favorites, grid, settings, search
        case card(String)
    }

    @State private var selection = TabID.grid
    @State private var gridWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    public init(@ViewBuilder page: @escaping (PlatformAppearanceDemoPage, CGFloat) -> Content) {
        self.page = page
    }

    public var body: some View {
        switch PlatformAppearanceDemo.session {
        case .success(let session):
            navigation(session)
                .environment(\.platformAppearanceLibrary, session.library)
                .environment(session.platforms)
                .environment(session.availability)
                .defaultAppStorage(session.defaults)
        case .failure:
            ContentUnavailableView("无法准备外观演示", systemImage: "exclamationmark.triangle")
        }
    }

    private var grid: some View {
        page(.grid, gridWidth)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    @ViewBuilder
    private func navigation(_ session: PlatformAppearanceDemo.Session) -> some View {
        #if os(tvOS)
        grid
        #else
        if #available(iOS 18, *) {
            tabs(session)
        } else {
            grid
        }
        #endif
    }

    #if os(iOS)
    @available(iOS 26, *)
    private var searchRole: TabRole {
        if #available(iOS 27, *) { return .prominent }
        return .search
    }
    #endif

    #if !os(tvOS)
    @available(iOS 18, *)
    private func tabs(_ session: PlatformAppearanceDemo.Session) -> some View {
        let platforms = session.library.store.orderedPlatforms(session.platforms.platformInfo)
        let icons = session.sidebarIcons
        let request = icons.request(platforms: platforms, catalogRevision: 0, dark: colorScheme == .dark)
        #if os(macOS)
        let side: CGFloat = 18
        let includesSidebar = true
        #else
        let side: CGFloat = 25
        let includesSidebar = sizeClass == .regular
        #endif

        return TabView(selection: $selection) {
            #if os(iOS)
            Tab("收藏", systemImage: "bookmark.fill", value: TabID.favorites) {
                ContentUnavailableView("暂无收藏", systemImage: "bookmark")
            }
            #endif

            Tab(includesSidebar ? "全部配置" : "配置", systemImage: "square.grid.2x2.fill", value: TabID.grid) {
                grid
            }

            if includesSidebar {
                TabSection("平台") {
                    ForEach(platforms, id: \.pluginId) { platform in
                        Tab(value: TabID.card(platform.pluginId)) {
                            page(.card(platform), gridWidth)
                        } label: {
                            Label {
                                Text(verbatim: platform.title)
                            } icon: {
                                icons.image(for: platform, side: side, displayScale: displayScale)
                            }
                        }
                    }
                }
            }

            #if os(iOS)
            if #available(iOS 26, *) {
                Tab("搜索", systemImage: "magnifyingglass", value: TabID.search, role: searchRole) {
                    ContentUnavailableView.search
                }
            } else {
                Tab("搜索", systemImage: "magnifyingglass", value: TabID.search) {
                    ContentUnavailableView.search
                }
            }

            #endif
            Tab("设置", systemImage: "gearshape.fill", value: TabID.settings) {
                page(.settings, gridWidth)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task(id: request) { await icons.load(request, side: side, displayScale: displayScale) }
    }
    #endif
}
#endif
