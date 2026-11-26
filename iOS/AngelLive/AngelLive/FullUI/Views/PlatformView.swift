import SwiftUI
import AngelLiveCore
import SharedAssets

struct PlatformView: View {
    var body: some View {
        AdaptivePlatformView()
    }
}

struct IOSPlatformGrid: View {
    let platforms: [Platformdescription]
    let catalogRevision: UInt
    let open: (Platformdescription) -> Void
    let customize: (Platformdescription) -> Void

    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    var body: some View {
        let idiom: PlatformDeviceIdiom = AppConstants.Device.isIPad ? .pad : .phone
        let snapshot = store.snapshot
        let ordered = store.orderedPlatforms(platforms)
        let ids = ordered.map(\.pluginId)
        let spacing = AppConstants.Spacing.lg
        ScrollView {
            PlatformAppearanceGridLayout(
                idiom: idiom, density: snapshot.gridDensity, aspect: snapshot.cardAspect,
                metrics: snapshot.metrics(for: idiom), spacing: spacing, horizontalPadding: spacing
            ) {
                ForEach(ordered) { platform in
                    let appearance = snapshot.appearance(for: platform.pluginId)
                    Button {
                        open(platform)
                    } label: {
                        PlatformAppearanceCard(
                            pluginID: platform.pluginId, title: platform.title, liveType: platform.liveType,
                            appearance: appearance, snapshot: snapshot, idiom: idiom,
                            defaultBackground: .shared("platform-bg"), catalogRevision: catalogRevision
                        )
                        .shadow(color: AppConstants.Shadow.lg.color, radius: AppConstants.Shadow.lg.radius,
                                x: AppConstants.Shadow.lg.x, y: AppConstants.Shadow.lg.y)
                    }
                    .buttonStyle(PlatformCardButtonStyle())
                    .contextMenu {
                        if store.isReady {
                            PlatformAppearanceCardActions(pluginID: platform.pluginId, orderedIDs: ids) {
                                customize(platform)
                            }
                        }
                    }
                    .accessibilityLabel(Text(verbatim: platform.title))
                    .accessibilityIdentifier("platform.card.\(platform.pluginId)")
                    .platformAppearanceGridSpan(appearance.spansTwoColumns)
                }
            }
            .padding(.vertical, spacing)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct PlatformCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(reduceMotion ? nil : .bouncy(duration: 0.3), value: configuration.isPressed)
    }
}

extension Platformdescription: @retroactive Identifiable {
    public var id: String { pluginId }
}

extension Notification.Name {
    static let switchToSettings = Notification.Name("switchToSettings")
}
