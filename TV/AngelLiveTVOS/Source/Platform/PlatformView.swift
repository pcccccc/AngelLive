import AngelLiveCore
import AngelLiveDependencies
import SharedAssets
import SwiftUI

extension LiveType: @retroactive Identifiable {
    public var id: String { rawValue }
}

struct PlatformView: View {
    @State private var platforms = PlatformViewModel()
    @State private var selectedPlatform: Platformdescription?
    @Environment(AppState.self) private var appViewModel

    var body: some View {
        Group {
            if appViewModel.pluginAvailability.hasAvailablePlugins {
                TVFullPlatformGrid(
                    platforms: platforms,
                    catalogRevision: appViewModel.pluginAvailability.catalogRevision,
                    usesSolidBackground: appViewModel.generalSettingsViewModel.generalDisableMaterialBackground,
                    open: { selectedPlatform = $0 }
                )
                .fullScreenCover(item: $selectedPlatform, content: platformDestination)
            } else {
                TVShellConfigView()
                    .environment(appViewModel)
            }
        }
        .task {
            await appViewModel.pluginAvailability.checkAvailability()
            platforms.refreshPlatforms(installedPluginIds: appViewModel.pluginAvailability.installedPluginIds)
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in
            Task { @MainActor in
                platforms.refreshPlatforms(installedPluginIds: appViewModel.pluginAvailability.installedPluginIds)
            }
        }
        .onChange(of: appViewModel.pluginAvailability.catalogRevision) { _, _ in
            platforms.refreshPlatforms(installedPluginIds: appViewModel.pluginAvailability.installedPluginIds)
        }
    }

    @ViewBuilder
    private func platformDestination(_ platform: Platformdescription) -> some View {
        if appViewModel.generalSettingsViewModel.generalDisableMaterialBackground {
            ListMainView(platform: platform, appViewModel: appViewModel)
                .background(Color("sl-background", bundle: nil))
                .safeAreaPadding(.all)
                .id("\(platform.id)-\(PlatformAPITokenService.shared.contentRevision)")
        } else {
            ListMainView(platform: platform, appViewModel: appViewModel)
                .id("\(platform.id)-\(PlatformAPITokenService.shared.contentRevision)")
        }
    }
}

struct TVFullPlatformGrid: View {
    let platforms: PlatformViewModel
    let catalogRevision: UInt
    let usesSolidBackground: Bool
    let open: (Platformdescription) -> Void

    @FocusState private var focus: FocusTarget?
    @State private var drawer: Drawer?
    @State private var returnFocus: FocusTarget?
    @State private var playlistArtworkRevision: UInt = 0
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    private enum FocusTarget: Hashable {
        case toolbar
        case card(String)
    }

    private enum Drawer: Hashable, Identifiable {
        case page
        case card(String)

        var id: Self { self }

        var platformID: String? {
            guard case let .card(id) = self else { return nil }
            return id
        }
    }

    private let horizontalInset: CGFloat = 80

    var body: some View {
        let ordered = store.snapshot.ordered(platforms.platformInfo, id: \.pluginId)
        GeometryReader { geometry in
            grid(ordered)
                .fullScreenCover(item: $drawer, onDismiss: restoreFocus) { presentedDrawer in
                    ZStack(alignment: .trailing) {
                        Color.black.opacity(0.22)
                            .ignoresSafeArea()
                            .accessibilityHidden(true)

                        drawerView(presentedDrawer, width: geometry.size.width * 0.46)
                    }
                    .presentationBackground(.clear)
                    .environment(\.platformAppearanceLibrary, library)
                    .interactiveDismissDisabled()
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in
            playlistArtworkRevision &+= 1
        }
    }

    private func drawerView(_ drawer: Drawer, width: CGFloat) -> some View {
        TVPlatformAppearanceControls(
            platforms: platforms,
            initialPlatformID: drawer.platformID,
            onClose: closeDrawer
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(width: width)
        .adaptiveGlassEffectRoundedRect(cornerRadius: 36)
        .padding(.vertical, 36)
        .padding(.trailing, horizontalInset)
    }

    private func restoreFocus() {
        guard drawer == nil, let target = returnFocus else { return }
        if case let .card(id) = target, !platforms.platformInfo.contains(where: { $0.pluginId == id }) {
            focus = .toolbar
        } else {
            focus = target
        }
        returnFocus = nil
    }

    private func grid(_ ordered: [Platformdescription]) -> some View {
        let snapshot = store.snapshot
        let order = ordered.map(\.pluginId)
        return ScrollView {
            HStack {
                Spacer(minLength: 0)
                Button("页面外观", systemImage: "slider.horizontal.3") {
                    openDrawer(.page, from: .toolbar)
                }
                .buttonBorderShape(.capsule)
                .opacity(drawer == nil ? 1 : 0)
                .disabled(!store.isReady)
                .focused($focus, equals: .toolbar)
                .accessibilityIdentifier("platform.appearance.open")
            }
            .focusSection()
            .padding(.horizontal, horizontalInset)
            .padding(.bottom, 14)

            PlatformAppearanceGridLayout(
                idiom: .tv, density: snapshot.gridDensity, aspect: snapshot.cardAspect,
                metrics: snapshot.metrics(for: .tv), spacing: 50, horizontalPadding: horizontalInset
            ) {
                ForEach(ordered) { platform in
                    let appearance = snapshot.appearance(for: platform.pluginId)
                    let target = FocusTarget.card(platform.pluginId)
                    Button {
                        if drawer == nil { open(platform) }
                    } label: {
                        PlatformAppearanceCard(
                            pluginID: platform.pluginId, title: platform.title, liveType: platform.liveType,
                            appearance: appearance, snapshot: snapshot, idiom: .tv,
                            defaultBackground: .shared("platform-bg"),
                            catalogRevision: artworkRevision(for: platform),
                            isFocused: focus == target
                        )
                        .overlay {
                            if focus == target {
                                focusDescription(platform, showsTitle: appearance.titleVisibility != .hidden)
                                    .clipShape(.rect(cornerRadius: snapshot.cardCornerRadius(for: .tv)))
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .buttonStyle(.card)
                    .buttonBorderShape(.roundedRectangle(radius: snapshot.cardCornerRadius(for: .tv)))
                    .focused($focus, equals: target)
                    .zIndex(focus == target ? 1 : 0)
                    .contextMenu {
                        if store.isReady, drawer == nil {
                            PlatformAppearanceCardActions(pluginID: platform.pluginId, orderedIDs: order) {
                                openDrawer(.card(platform.pluginId), from: target)
                            }
                        }
                    }
                    .onPlayPauseCommand {
                        guard store.isReady, drawer == nil, focus == target else { return }
                        openDrawer(.card(platform.pluginId), from: target)
                    }
                    .accessibilityLabel(Text(verbatim: platform.title))
                    .accessibilityIdentifier("platform.card.\(platform.pluginId)")
                    .platformAppearanceGridSpan(appearance.spansTwoColumns)
                }
            }
            .focusSection()
            .padding(.bottom, 42)
        }
        .padding(.top, 22)
        .scrollClipDisabled()
    }

    private func focusDescription(_ platform: Platformdescription, showsTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text(verbatim: platform.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)

            Text(verbatim: platform.descripiton)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(usesSolidBackground ? AnyShapeStyle(Color("sl-background", bundle: nil)) : AnyShapeStyle(.thinMaterial))
    }

    private func artworkRevision(for platform: Platformdescription) -> UInt {
        let revision = catalogRevision
        return PlaylistPlatformIdentity.isPlaylist(platform.liveType) ? revision &+ playlistArtworkRevision : revision
    }

    private func openDrawer(_ drawer: Drawer, from target: FocusTarget) {
        guard self.drawer == nil else { return }
        returnFocus = target
        self.drawer = drawer
    }

    private func closeDrawer() {
        drawer = nil
    }
}
