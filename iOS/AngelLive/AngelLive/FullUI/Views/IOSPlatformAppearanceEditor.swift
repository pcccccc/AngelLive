import AngelLiveCore
import SharedAssets
import SwiftUI

struct IOSPlatformAppearancePage: View {
    var showsDone = false
    var gridWidth: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(PlatformViewModel.self) private var platforms
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @State private var confirmsReset = false
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }
    private let background = Image.shared("platform-bg")

    private var idiom: PlatformDeviceIdiom { AppConstants.Device.isIPad ? .pad : .phone }

    var body: some View {
        let ordered = store.orderedPlatforms(platforms.platformInfo)
        List {
            if let platform = ordered.first {
                Section {
                    PlatformAppearancePreview(
                        platform: platform,
                        idiom: idiom,
                        defaultBackground: background,
                        catalogRevision: pluginAvailability.catalogRevision,
                        width: 188,
                        gridWidth: gridWidth,
                        gridSpacing: AppConstants.Spacing.lg,
                        gridPadding: AppConstants.Spacing.lg
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            PlatformAppearancePageSections(idiom: idiom, defaultBackground: background)
            if !ordered.isEmpty {
                Section("平台顺序与单卡管理") {
                    ForEach(ordered) { platform in
                        NavigationLink {
                            IOSPlatformAppearanceCardEditor(platform: platform, gridWidth: gridWidth)
                        } label: {
                            LabeledContent {
                                Text(store.snapshot.appearance(for: platform.pluginId).logoMode.appearanceTitle)
                            } label: {
                                HStack(spacing: 10) {
                                    PlatformAppearanceRowIcon(platform: platform, side: 24)
                                    Text(verbatim: platform.title)
                                }
                            }
                        }
                    }
                    .onMove { indices, destination in
                        var ids = ordered.map(\.pluginId)
                        ids.move(fromOffsets: indices, toOffset: destination)
                        store.setOrder(ids)
                    }
                }
            }
            if library == nil {
                Section("iCloud 外观同步") { IOSPlatformAppearanceSyncControls() }
            }
            Section {
                Button("恢复全部默认", role: .destructive) { confirmsReset = true }
            }
        }
        .tint(AppConstants.Colors.accent)
        .disabled(!store.isReady)
        .listStyle(.insetGrouped)
        .navigationTitle("配置页外观")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
                    .accessibilityIdentifier("platform.appearance.editOrder")
            }
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("platform.appearance.done")
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
        .overlay {
            if !store.isReady {
                if store.persistenceFailed {
                    ContentUnavailableView("无法读取外观设置", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - Single Card

struct IOSPlatformAppearanceCardEditor: View {
    let platform: Platformdescription
    var showsDone = false
    var gridWidth: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(PlatformViewModel.self) private var platforms
    @Environment(PluginAvailabilityService.self) private var pluginAvailability
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }
    private let background = Image.shared("platform-bg")

    private var idiom: PlatformDeviceIdiom { AppConstants.Device.isIPad ? .pad : .phone }

    var body: some View {
        List {
            Section {
                PlatformAppearancePreview(
                    platform: platform,
                    idiom: idiom,
                    defaultBackground: background,
                    catalogRevision: pluginAvailability.catalogRevision,
                    width: 188,
                    gridWidth: gridWidth,
                    gridSpacing: AppConstants.Spacing.lg,
                    gridPadding: AppConstants.Spacing.lg
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
            PlatformAppearanceCardSections(
                platform: platform,
                orderedIDs: store.orderedPlatforms(platforms.platformInfo).map(\.pluginId),
                defaultBackground: background
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle(platform.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("platform.card.done")
                }
            }
        }
    }
}

// MARK: - iCloud Sync

struct IOSPlatformAppearanceSyncControls: View {
    var usesSyncCardLayout = false
    @ObservedObject private var master = PlatformCredentialSyncService.shared
    @AppStorage(PlatformAppearanceSyncService.settingKey) private var enabled = true
    private let syncStatus = PlatformAppearanceSyncService.status

    var body: some View {
        IOSPlatformAppearanceSyncRows(
            usesSyncCardLayout: usesSyncCardLayout,
            enabled: $enabled,
            masterEnabled: master.iCloudSyncEnabled,
            isSyncing: syncStatus.isSyncing,
            message: PlatformAppearanceSyncStateLabel(enabled: enabled, masterEnabled: master.iCloudSyncEnabled).message,
            syncNow: { Task { await PlatformAppearanceSyncService.shared.sync() } }
        )
    }
}

struct IOSPlatformAppearanceSyncRows: View {
    let usesSyncCardLayout: Bool
    @Binding var enabled: Bool
    let masterEnabled: Bool
    let isSyncing: Bool
    let message: Text
    let syncNow: () -> Void

    var body: some View {
        if usesSyncCardLayout {
            VStack(alignment: .leading, spacing: AppConstants.Spacing.md) {
                controls
            }
            .padding()
            .background(AppConstants.Colors.materialBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppConstants.CornerRadius.lg, style: .continuous))
        } else {
            controls
        }
    }

    @ViewBuilder
    private var controls: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("配置页外观同步")
                    .font(.headline)
                    .foregroundStyle(AppConstants.Colors.primaryText)
                message
                    .font(.caption)
                    .foregroundStyle(AppConstants.Colors.secondaryText)
            }
        }
        .tint(AppConstants.Colors.accent)
        .disabled(!masterEnabled)
        .accessibilityIdentifier("platform.appearance.sync.toggle")
        if usesSyncCardLayout { Divider() }
        Group {
            if usesSyncCardLayout {
                Button(action: syncNow) {
                    ICloudSyncActionRow(
                        title: "立即同步外观",
                        subtitle: "同步平台顺序、卡片样式和图片",
                        isLoading: isSyncing,
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button(
                    "立即同步外观",
                    systemImage: "arrow.clockwise",
                    action: syncNow
                )
            }
        }
        .disabled(!masterEnabled || !enabled || isSyncing)
        .accessibilityIdentifier("platform.appearance.sync.now")
    }
}
