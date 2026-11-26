import AngelLiveCore
import SharedAssets
import SwiftUI

struct PlatformView: View {
    let open: (Platformdescription) -> Void

    @Environment(PlatformViewModel.self) private var platforms
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @State private var showingAppearance = false
    @State private var showingManagement = false
    @State private var selectedCard: Platformdescription?
    @State private var gridWidth: CGFloat = 0
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    var body: some View {
        let snapshot = store.snapshot
        let ordered = store.orderedPlatforms(platforms.platformInfo)
        let order = ordered.map(\.pluginId)
        ScrollView {
            PlatformAppearanceGridLayout(
                idiom: .mac, density: snapshot.gridDensity, aspect: snapshot.cardAspect,
                metrics: snapshot.metrics(for: .mac), spacing: 16, horizontalPadding: 20
            ) {
                ForEach(ordered, id: \.pluginId) { platform in
                    let appearance = snapshot.appearance(for: platform.pluginId)
                    Button { open(platform) } label: {
                        PlatformAppearanceCard(
                            pluginID: platform.pluginId, title: platform.title, liveType: platform.liveType,
                            appearance: appearance, snapshot: snapshot, idiom: .mac,
                            defaultBackground: .shared("platform-bg"), catalogRevision: pluginAvailability.catalogRevision
                        )
                    }
                    .buttonStyle(MacPlatformCardButtonStyle())
                    .contextMenu {
                        if store.isReady {
                            PlatformAppearanceCardActions(pluginID: platform.pluginId, orderedIDs: order) {
                                selectedCard = platform
                            }
                        }
                    }
                    .accessibilityLabel(Text(verbatim: platform.title))
                    .accessibilityIdentifier("platform.card.\(platform.pluginId)")
                    .platformAppearanceGridSpan(appearance.spansTwoColumns)
                }
            }
            .padding(.vertical, 20)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        .navigationTitle("全部配置")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("列数密度", selection: Binding(
                    get: { store.snapshot.gridDensity },
                    set: { store.updateGlobal(\.gridDensity, to: $0) }
                )) {
                    ForEach(PlatformGridDensity.allCases, id: \.self) { Text($0.appearanceTitle).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!store.isReady || snapshot.metrics(for: .mac).useCustomMetrics)

                Button("配置页外观", systemImage: "slider.horizontal.3") { showingAppearance.toggle() }
                    .accessibilityIdentifier("platform.appearance.open")
                    .popover(isPresented: $showingAppearance, arrowEdge: .top) {
                        MacPlatformAppearancePopover {
                            showingAppearance = false
                            showingManagement = true
                        }
                        .disabled(!store.isReady)
                    }
            }
        }
        .sheet(isPresented: $showingManagement) {
            MacPlatformAppearanceSettingsSheet(gridWidth: gridWidth)
        }
        .sheet(isPresented: Binding(
            get: { selectedCard != nil },
            set: { if !$0 { selectedCard = nil } }
        )) {
            if let selectedCard {
                MacPlatformAppearanceCardSheet(platform: selectedCard, gridWidth: gridWidth)
            }
        }
    }
}

private struct MacPlatformCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(isHovered ? 0.035 : 0)
            .shadow(color: .black.opacity(isHovered ? 0.14 : 0.08), radius: 6, y: 2)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}
