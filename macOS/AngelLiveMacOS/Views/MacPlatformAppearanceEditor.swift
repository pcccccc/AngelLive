import AngelLiveCore
import SharedAssets
import SwiftUI

// MARK: - Toolbar Popover

struct MacPlatformAppearancePopover: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("配置页外观")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                PlatformAppearanceGridControls(idiom: .mac)
            }
            .padding(10)
            .background(.background.secondary, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 12) {
                Text("卡片背景")
                    .font(.subheadline.weight(.semibold))

                PlatformAppearanceBackgroundControls(defaultBackground: .shared("platform-bg"))
            }
            .padding(10)
            .background(.background.secondary, in: .rect(cornerRadius: 10))

            Button("平台排序与完整设置…", action: openSettings)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .modifier(MacFullUIFormControls(usesFullUI: true))
        .padding(14)
        .frame(width: 348)
    }
}

// MARK: - Settings

struct MacPlatformAppearancePage: View {
    let openCard: (Platformdescription) -> Void
    @Environment(PlatformViewModel.self) private var platforms
    @State private var confirmsReset = false
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }
    private let background = Image.shared("platform-bg")

    var body: some View {
        let ordered = store.orderedPlatforms(platforms.platformInfo)
        let ids = ordered.map(\.pluginId)
        Form {
            PlatformAppearancePageSections(idiom: .mac, defaultBackground: background)
            if !ordered.isEmpty {
                Section("平台顺序与单卡管理") {
                    ForEach(ordered, id: \.pluginId) { platform in
                        HStack {
                            Button {
                                openCard(platform)
                            } label: {
                                HStack(spacing: 8) {
                                    PlatformAppearanceRowIcon(platform: platform, side: 20)
                                    Text(verbatim: platform.title)
                                    Spacer()
                                    Text(store.snapshot.appearance(for: platform.pluginId).logoMode.appearanceTitle)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            Button("前移一位", systemImage: "arrow.up") {
                                store.move(
                                    platform.pluginId,
                                    by: -1,
                                    among: ids
                                )
                            }
                            .disabled(platform.pluginId == ids.first)
                            Button("后移一位", systemImage: "arrow.down") {
                                store.move(
                                    platform.pluginId,
                                    by: 1,
                                    among: ids
                                )
                            }
                            .disabled(platform.pluginId == ids.last)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            }
            if library == nil {
                Section("iCloud 外观同步") { MacPlatformAppearanceSyncRows() }
            }
            Section {
                Button("恢复全部默认", role: .destructive) { confirmsReset = true }
            }
        }
        .formStyle(.grouped)
        .modifier(MacFullUIFormControls(usesFullUI: true))
        .disabled(!store.isReady)
        .overlay {
            if !store.isReady {
                if store.persistenceFailed {
                    ContentUnavailableView("无法读取外观设置", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                }
            }
        }
        .confirmationDialog(
            "恢复配置页默认外观？",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("恢复全部默认", role: .destructive) {
                store.resetAll(defaultOrder: platforms.platformInfo.map(\.pluginId))
            }
            Button("取消", role: .cancel) {}
        }
    }
}

struct MacPlatformAppearanceSettingsSheet: View {
    let gridWidth: CGFloat
    @State private var selected: Platformdescription?

    var body: some View {
        MacPlatformAppearancePage { selected = $0 }
            .sheet(
                isPresented: Binding(
                    get: { selected != nil },
                    set: { if !$0 { selected = nil } }
                )
            ) {
                if let selected { MacPlatformAppearanceCardSheet(platform: selected, gridWidth: gridWidth) }
            }
            .macSettingsPage("配置页外观")
            .frame(
                minWidth: 520,
                idealWidth: 580,
                minHeight: 460,
                idealHeight: 580
            )
            .macSettingsSheetPresentation()
    }
}

// MARK: - Single Card

struct MacPlatformAppearanceCardSheet: View {
    let platform: Platformdescription
    let gridWidth: CGFloat

    var body: some View {
        MacPlatformAppearanceCardEditor(platform: platform, gridWidth: gridWidth)
            .macSettingsPage(platform.title)
            .frame(
                minWidth: 600,
                idealWidth: 640,
                minHeight: 460,
                idealHeight: 520
            )
            .macSettingsSheetPresentation()
    }
}

struct MacPlatformAppearanceCardEditor: View {
    let platform: Platformdescription
    let gridWidth: CGFloat

    @Environment(PlatformViewModel.self) private var platforms
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }
    private let background = Image.shared("platform-bg")

    var body: some View {
        HStack(spacing: 0) {
            PlatformAppearancePreview(
                platform: platform,
                idiom: .mac,
                defaultBackground: background,
                catalogRevision: pluginAvailability.catalogRevision,
                width: 188,
                gridWidth: gridWidth,
                gridSpacing: 16,
                gridPadding: 20
            )
            .padding(16)
            .frame(width: 236)
            Divider()
            Form {
                PlatformAppearanceCardSections(
                    platform: platform,
                    orderedIDs: store.orderedPlatforms(platforms.platformInfo).map(\.pluginId),
                    defaultBackground: background
                )
            }
            .formStyle(.grouped)
            .modifier(MacFullUIFormControls(usesFullUI: true))
            .contentMargins(
                .all,
                16,
                for: .scrollContent
            )
        }
    }
}

// MARK: - iCloud Sync

struct MacPlatformAppearanceSyncRows: View {
    @ObservedObject private var master = PlatformCredentialSyncService.shared
    @AppStorage(PlatformAppearanceSyncService.settingKey) private var enabled = true
    private let syncStatus = PlatformAppearanceSyncService.status

    var body: some View {
        MacPlatformAppearanceSyncContent(
            enabled: $enabled,
            masterEnabled: master.iCloudSyncEnabled,
            isSyncing: syncStatus.isSyncing,
            message: PlatformAppearanceSyncStateLabel(enabled: enabled, masterEnabled: master.iCloudSyncEnabled).message,
            syncNow: { Task { await PlatformAppearanceSyncService.shared.sync() } }
        )
    }
}

struct MacPlatformAppearanceSyncContent: View {
    @Binding var enabled: Bool
    let masterEnabled: Bool
    let isSyncing: Bool
    let message: Text
    let syncNow: () -> Void

    var body: some View {
        Toggle(isOn: $enabled) {
            PanelNavigationRow(title: "配置页外观 iCloud 同步", showsChevron: false) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.cyan.gradient)
            }
        }
        .toggleStyle(.switch)
        .tint(AppConstants.Colors.accent)
        .disabled(!masterEnabled)
        .accessibilityIdentifier("platform.appearance.sync.toggle")

        Button(action: syncNow) {
            PanelNavigationRow(title: "立即同步外观") {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.cyan.gradient)
            } trailing: {
                message
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!masterEnabled || !enabled || isSyncing)
        .accessibilityIdentifier("platform.appearance.sync.now")
    }
}
