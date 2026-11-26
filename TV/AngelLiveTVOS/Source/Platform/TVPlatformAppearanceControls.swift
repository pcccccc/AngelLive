import AngelLiveCore
import SwiftUI

struct TVPlatformAppearanceControls: View {
    let platforms: PlatformViewModel
    var initialPlatformID: String?

    var onInitialFocus: () -> Void = {}
    let onClose: () -> Void

    @State private var selectedPlatformID: String?
    @State private var showsGlobalControls = false
    @State private var confirmsReset = false
    @FocusState private var focus: InitialControl?
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }
    private enum InitialControl: Hashable { case page, card }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("配置页外观")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if selectedPlatform != nil {
                    Button("全局网格设置") {
                        selectedPlatformID = nil
                        showsGlobalControls = true
                    }
                    .accessibilityIdentifier("platform.appearance.global")
                }
                Button(
                    "关闭",
                    systemImage: "xmark",
                    action: onClose
                )
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("platform.appearance.close")
            }
            .padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let selectedPlatform {
                        cardControls(selectedPlatform)
                    } else {
                        pageControls
                        platformChooser
                    }
                    Text("在 iPhone、iPad 或 Mac 设置自定义图片后，将通过 iCloud 自动同步至 Apple TV。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .disabled(!store.isReady)
            .overlay {
                if !store.isReady {
                    if store.persistenceFailed {
                        Text("无法读取外观设置")
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .focusScope(focusScope)
        .onChange(of: selectedPlatform?.pluginId) { _, selectedID in
            focus = selectedID == nil ? .page : .card
        }
        .defaultFocus($focus, selectedPlatform == nil ? .page : .card)
        .task(id: store.isReady) {
            if store.isReady { focus = selectedPlatform == nil ? .page : .card }
        }
        .onChange(of: focus) { _, focus in
            if focus != nil { onInitialFocus() }
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

    @Namespace private var focusScope
    private var selectedPlatform: Platformdescription? {
        guard !showsGlobalControls, let id = selectedPlatformID ?? initialPlatformID else { return nil }
        return platforms.platformInfo.first { $0.pluginId == id }
    }

    private var pageControls: some View {
        let snapshot = store.snapshot
        let metrics = snapshot.metrics(for: .tv)
        return Group {
            sectionHeader("全局网格")
            Button {
                var next = metrics
                next.useCustomMetrics.toggle()
                store.updateMetrics(next, for: .tv)
            } label: {
                TVAppearanceControlLabel(
                    "自定义电视端尺寸",
                    value: Text(metrics.useCustomMetrics ? "已开启" : "已关闭"),
                    hasChevron: false
                )
            }
            .focused($focus, equals: .page)

            if metrics.useCustomMetrics {
                metricMenu(
                    "每行列数",
                    selection: metrics.columns,
                    values: Array(PlatformDeviceIdiom.tv.columnRange)
                ) {
                    var next = metrics
                    next.columns = $0
                    store.updateMetrics(next, for: .tv)
                }
                metricMenu(
                    "卡片高度",
                    selection: Int(metrics.cardHeight),
                    values: Array(
                        stride(
                            from: 180,
                            through: 300,
                            by: 10
                        )
                    )
                ) {
                    var next = metrics
                    next.cardHeight = Double($0)
                    store.updateMetrics(next, for: .tv)
                }
                metricMenu(
                    "卡片圆角",
                    selection: Int(metrics.cornerRadius),
                    values: Array(16...32)
                ) {
                    var next = metrics
                    next.cornerRadius = Double($0)
                    store.updateMetrics(next, for: .tv)
                }
            } else {
                Menu {
                    ForEach(PlatformGridDensity.allCases, id: \.self) { density in
                        choice(density.appearanceTitle, selected: density == snapshot.gridDensity) {
                            store.updateGlobal(\.gridDensity, to: density)
                        }
                    }
                } label: {
                    TVAppearanceControlLabel("列数密度", value: Text(snapshot.gridDensity.appearanceTitle))
                }
                Menu {
                    ForEach(PlatformCardAspectPreset.allCases, id: \.self) { aspect in
                        choice(aspect.appearanceTitle, selected: aspect == snapshot.cardAspect) {
                            store.updateGlobal(\.cardAspect, to: aspect)
                        }
                    }
                } label: {
                    TVAppearanceControlLabel("卡片比例", value: Text(snapshot.cardAspect.appearanceTitle))
                }
            }
            backgroundMenu(
                "全局卡片背景",
                selection: snapshot.globalBackground,
                includesInherit: false
            ) { style in
                if let style { store.updateGlobal(\.globalBackground, to: style) }
            }
            actionRow(
                "恢复全部默认",
                symbol: "arrow.counterclockwise",
                role: .destructive
            ) { confirmsReset = true }
        }
    }

    private var platformChooser: some View {
        Menu {
            ForEach(store.snapshot.ordered(platforms.platformInfo, id: \.pluginId)) { platform in
                Button(platform.title) {
                    selectedPlatformID = platform.pluginId
                    showsGlobalControls = false
                }
            }
        } label: {
            TVAppearanceControlLabel(
                "单卡外观",
                value: Text("选择平台")
            )
        }
        .disabled(platforms.platformInfo.isEmpty)
    }

    private func cardControls(_ platform: Platformdescription) -> some View {
        let id = platform.pluginId
        let appearance = store.snapshot.appearance(for: id)
        let order = store.snapshot.ordered(platforms.platformInfo, id: \.pluginId).map(\.pluginId)
        return Group {
            Text(verbatim: platform.title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Menu {
                Button("自动") { setLogo(.auto, for: id) }
                Button("系统符号") { setLogo(.symbol(name: "tv", tintHex: nil), for: id) }
                Button("缩写徽章") {
                    let glyph = PluginManagementMonogramStyle(pluginID: id, displayName: platform.title).glyph
                    setLogo(.monogramBadge(text: glyph, tintHex: nil), for: id)
                }
            } label: {
                TVAppearanceControlLabel("图标样式", value: Text(appearance.logoMode.appearanceTitle))
            }
            .focused($focus, equals: .card)

            switch appearance.logoMode {
            case let .symbol(name, tint):
                Menu {
                    ForEach(PlatformAppearanceOptions.symbols) { symbol in
                        Button {
                            setLogo(.symbol(name: symbol.id, tintHex: tint), for: id)
                        } label: {
                            Label {
                                Text(symbol.title)
                            } icon: {
                                Image(systemName: symbol.id)
                            }
                        }
                    }
                } label: {
                    TVAppearanceControlLabel("选择符号", value: Image(systemName: name))
                }
                accentMenu(tint) { setLogo(.symbol(name: name, tintHex: $0), for: id) }
            case let .monogramBadge(text, tint):
                TextField(
                    "徽章文字（最多 3 个字符）",
                    text: Binding(
                        get: { text },
                        set: { setLogo(.monogramBadge(text: $0, tintHex: tint), for: id) }
                    )
                )
                accentMenu(tint) { setLogo(.monogramBadge(text: text, tintHex: $0), for: id) }
            default: EmptyView()
            }

            Menu {
                ForEach(PlatformTitleVisibility.allCases, id: \.self) { visibility in
                    choice(visibility.appearanceTitle, selected: visibility == appearance.titleVisibility) {
                        store.updateCard(id) { $0.titleVisibility = visibility }
                    }
                }
            } label: {
                TVAppearanceControlLabel("卡片标题", value: Text(appearance.titleVisibility.appearanceTitle))
            }

            backgroundMenu(
                "专属背景",
                selection: appearance.backgroundOverride,
                includesInherit: true
            ) { style in
                store.updateCard(id) { $0.backgroundOverride = style }
            }

            Button {
                store.updateCard(id) { $0.spansTwoColumns.toggle() }
            } label: {
                TVAppearanceControlLabel(
                    "跨两列展示",
                    value: Text(appearance.spansTwoColumns ? "已开启" : "已关闭"),
                    hasChevron: false
                )
            }
            actionRow("前移一位", symbol: "arrow.up") {
                store.move(
                    id,
                    by: -1,
                    among: order
                )
            }
            .disabled(id == order.first)
            actionRow("后移一位", symbol: "arrow.down") {
                store.move(
                    id,
                    by: 1,
                    among: order
                )
            }
            .disabled(id == order.last)
            actionRow(
                "恢复此平台默认",
                symbol: "arrow.counterclockwise",
                role: .destructive
            ) { store.resetCard(id) }
            .disabled(store.snapshot.cardOverrides[id] == nil)
        }
    }

    // MARK: - Drawer Controls

    private func actionRow(
        _ title: LocalizedStringKey,
        symbol: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func backgroundMenu(
        _ title: LocalizedStringKey,
        selection: PlatformBackgroundStyle?,
        includesInherit: Bool,
        change: @escaping (PlatformBackgroundStyle?) -> Void
    ) -> some View {
        Menu {
            if includesInherit { choice("跟随全局", selected: selection == nil) { change(nil) } }
            ForEach(PlatformBackgroundStyle.appearancePresets, id: \.self) { style in
                choice(style.appearanceTitle, selected: style == selection) { change(style) }
            }
        } label: {
            TVAppearanceControlLabel(title, value: Text(selection?.appearanceTitle ?? "跟随全局"))
        }
    }

    private func accentMenu(_ tint: String?, change: @escaping (String?) -> Void) -> some View {
        Menu {
            Button("自动") { change(nil) }
            ForEach(PlatformAppearanceOptions.accents) { accent in
                Button {
                    change(accent.id)
                } label: {
                    Text(accent.title)
                }
            }
        } label: {
            TVAppearanceControlLabel(
                "主题色",
                value:
                    PlatformAppearanceOptions.accents.first { $0.id == tint }.map { Text($0.title) }
                    ?? Text("自动")
            )
        }
    }

    private func metricMenu(
        _ title: LocalizedStringKey,
        selection: Int,
        values: [Int],
        change: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in
                choice("\(value)", selected: value == selection) { change(value) }
            }
        } label: {
            TVAppearanceControlLabel(title, value: Text(selection, format: .number))
        }
    }

    private func choice(
        _ title: LocalizedStringKey,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func setLogo(_ logo: PlatformLogoMode, for platformID: String) {
        store.updateCard(platformID) { $0.logoMode = logo }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

struct TVAppearanceControlLabel<Value: View>: View {
    let title: LocalizedStringKey
    let value: Value
    let hasChevron: Bool

    init(
        _ title: LocalizedStringKey,
        value: Value,
        hasChevron: Bool = true
    ) {
        self.title = title
        self.value = value
        self.hasChevron = hasChevron
    }

    var body: some View {
        HStack(spacing: 15) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            value
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if hasChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings Entry

struct TVSettingsPlatformAppearance: View {
    let close: () -> Void
    @Environment(AppState.self) private var app
    @State private var platforms = PlatformViewModel()

    var body: some View {
        TVPlatformAppearanceControls(platforms: platforms, onClose: close)
            .task(id: app.pluginAvailability.catalogRevision) { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in refresh()
            }
    }

    private func refresh() {
        platforms.refreshPlatforms(installedPluginIds: app.pluginAvailability.installedPluginIds)
    }
}
