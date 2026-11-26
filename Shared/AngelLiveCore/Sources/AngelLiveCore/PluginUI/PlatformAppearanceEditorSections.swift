#if !os(tvOS)
import SwiftUI
#if os(iOS)
import PhotosUI
#else
import UniformTypeIdentifiers
#endif

// MARK: - Page

public struct PlatformAppearancePageSections: View {
    let idiom: PlatformDeviceIdiom
    let defaultBackground: Image

    public init(idiom: PlatformDeviceIdiom, defaultBackground: Image) {
        self.idiom = idiom
        self.defaultBackground = defaultBackground
    }

    public var body: some View {
        Section("全局卡片背景") {
            PlatformAppearanceBackgroundControls(defaultBackground: defaultBackground)
        }

        Section("网格密度与比例") {
            PlatformAppearanceGridControls(idiom: idiom)
        }
    }
}

public struct PlatformAppearanceBackgroundControls: View {
    let defaultBackground: Image
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    public init(defaultBackground: Image) {
        self.defaultBackground = defaultBackground
    }

    public var body: some View {
        PlatformAppearanceBackgroundChoices(
            selection: Binding(
                get: { store.snapshot.globalBackground },
                set: { store.updateGlobal(\.globalBackground, to: $0 ?? .defaultAsset) }
            ),
            defaultBackground: defaultBackground
        )

        AppearancePhotoPicker(kind: .background, title: "选择背景图片") { id in
            store.updateGlobal(\.globalBackground, to: .customImage(assetID: id, focalY: 0.5))
        }

        if case let .customImage(id, focalY) = store.snapshot.globalBackground {
            AppearanceSlider(
                title: "纵向取景位置",
                value: Binding(
                    get: { focalY * 100 },
                    set: {
                        store.updateGlobal(
                            \.globalBackground,
                            to: .customImage(assetID: id, focalY: $0 / 100)
                        )
                    }
                ),
                range: 0...100,
                unit: "%"
            )
        }

        AppearanceSlider(
            title: "背景柔化",
            value: Binding(
                get: { store.snapshot.backgroundBlurRadius },
                set: { store.updateGlobal(\.backgroundBlurRadius, to: $0.rounded()) }
            ),
            range: 0...20,
            unit: "pt"
        )

        Toggle(
            "背景对比度保护",
            isOn: Binding(
                get: { store.snapshot.contrastScrimEnabled },
                set: { store.updateGlobal(\.contrastScrimEnabled, to: $0) }
            )
        )
    }
}

public struct PlatformAppearanceGridControls: View {
    let idiom: PlatformDeviceIdiom
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    public init(idiom: PlatformDeviceIdiom) {
        self.idiom = idiom
    }

    private var metrics: PlatformIdiomCustomMetrics {
        store.snapshot.metrics(for: idiom)
    }

    public var body: some View {
        Toggle(
            "自定义本机尺寸",
            isOn: Binding(
                get: { metrics.useCustomMetrics },
                set: { value in updateMetrics { $0.useCustomMetrics = value } }
            )
        )

        if metrics.useCustomMetrics {
            Picker(
                "每行列数",
                selection: Binding(
                    get: { metrics.columns },
                    set: { value in updateMetrics { $0.columns = value } }
                )
            ) {
                ForEach(idiom.columnRange, id: \.self) { count in
                    Text("\(count) 列")
                        .tag(count)
                }
            }
            .pickerStyle(.segmented)

            AppearanceSlider(
                title: "卡片高度",
                value: Binding(
                    get: { metrics.cardHeight },
                    set: { value in updateMetrics { $0.cardHeight = value.rounded() } }
                ),
                range: idiom.cardHeightRange,
                unit: "pt"
            )

            AppearanceSlider(
                title: "卡片圆角",
                value: Binding(
                    get: { metrics.cornerRadius },
                    set: { value in updateMetrics { $0.cornerRadius = value.rounded() } }
                ),
                range: idiom.cornerRadiusRange,
                unit: "pt"
            )
        } else {
            Picker(
                "列数密度",
                selection: Binding(
                    get: { store.snapshot.gridDensity },
                    set: { store.updateGlobal(\.gridDensity, to: $0) }
                )
            ) {
                ForEach(PlatformGridDensity.allCases, id: \.self) { density in
                    Text(density.appearanceTitle)
                        .tag(density)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("platform.appearance.density")

            Picker(
                "卡片比例",
                selection: Binding(
                    get: { store.snapshot.cardAspect },
                    set: { store.updateGlobal(\.cardAspect, to: $0) }
                )
            ) {
                ForEach(PlatformCardAspectPreset.allCases, id: \.self) { aspect in
                    Text(aspect.appearanceTitle)
                        .tag(aspect)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func updateMetrics(_ change: (inout PlatformIdiomCustomMetrics) -> Void) {
        var next = metrics
        change(&next)
        store.updateMetrics(next, for: idiom)
    }
}

private struct AppearanceSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(Int(value.rounded())) \(unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            Slider(value: $value, in: range)
                .accessibilityLabel(Text(title))
                .accessibilityValue("\(Int(value.rounded())) \(unit)")
        }
    }
}

// MARK: - Card

public struct PlatformAppearanceCardSections: View {
    let platform: Platformdescription
    let orderedIDs: [String]
    let defaultBackground: Image

    @State private var logoChoice: LogoChoice?
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    private enum LogoChoice: String, CaseIterable, Hashable {
        case auto, symbol, badge, photo

        init(_ mode: PlatformLogoMode) {
            switch mode {
            case .auto: self = .auto
            case .symbol: self = .symbol
            case .monogramBadge: self = .badge
            case .customImage: self = .photo
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .auto: "自动"
            case .symbol: "符号"
            case .badge: "缩写"
            case .photo: "图片"
            }
        }
    }

    public init(
        platform: Platformdescription,
        orderedIDs: [String],
        defaultBackground: Image
    ) {
        self.platform = platform
        self.orderedIDs = orderedIDs
        self.defaultBackground = defaultBackground
    }

    public var body: some View {
        logoSection
        backgroundSection
        sizeSection
    }

    private var appearance: PlatformCardAppearanceOverride { store.snapshot.appearance(for: platform.pluginId) }

    private var logoSection: some View {
        Section("图标与标题") {
            Picker(
                "图标样式",
                selection: Binding(
                    get: { logoChoice ?? LogoChoice(appearance.logoMode) },
                    set: setLogoChoice
                )
            ) {
                ForEach(LogoChoice.allCases, id: \.self) {
                    Text($0.title)
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("platform.card.logoMode")
            switch logoChoice ?? LogoChoice(appearance.logoMode) {
            case .auto: EmptyView()
            case .symbol:
                Picker("选择符号", selection: symbolBinding) {
                    let name = symbolBinding.wrappedValue
                    if !PlatformAppearanceOptions.symbols.contains(where: { $0.id == name }) {
                        Label("当前符号", systemImage: name)
                            .tag(name)
                    }
                    ForEach(PlatformAppearanceOptions.symbols) { symbol in
                        Label {
                            Text(symbol.title)
                        } icon: {
                            Image(systemName: symbol.id)
                        }
                        .tag(symbol.id)
                    }
                }
                tintPicker
            case .badge:
                TextField("徽章文字（最多 3 个字符）", text: badgeBinding)
                    .accessibilityIdentifier("platform.card.monogram")
                tintPicker
            case .photo:
                AppearancePhotoPicker(kind: .logo, title: "选择图标图片") { id in
                    setLogo(.customImage(assetID: id))
                }
            }
            Picker(
                "卡片标题",
                selection: Binding(
                    get: { appearance.titleVisibility },
                    set: { value in store.updateCard(platform.pluginId) { $0.titleVisibility = value } }
                )
            ) {
                ForEach(PlatformTitleVisibility.allCases, id: \.self) {
                    Text($0.appearanceTitle)
                        .tag($0)
                }
            }
        }
        .onChange(of: appearance.logoMode) { _, mode in logoChoice = LogoChoice(mode) }
    }

    private var tintPicker: some View {
        Picker("主题色", selection: tintBinding) {
            Text("自动")
                .tag(String?.none)
            if let tint = tintBinding.wrappedValue, !PlatformAppearanceOptions.accents.contains(where: { $0.id == tint }) {
                Text("当前主题色")
                    .tag(Optional(tint))
            }
            ForEach(PlatformAppearanceOptions.accents) { accent in
                Label {
                    Text(accent.title)
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(PlatformRGBAColor(hex: accent.id)?.swiftUIColor ?? .primary)
                }
                .tag(Optional(accent.id))
            }
        }
    }

    private var backgroundSection: some View {
        Section("专属背景") {
            PlatformAppearanceBackgroundChoices(
                selection: Binding(
                    get: { appearance.backgroundOverride },
                    set: { value in store.updateCard(platform.pluginId) { $0.backgroundOverride = value } }
                ),
                platform: platform,
                defaultBackground: defaultBackground
            )
            AppearancePhotoPicker(kind: .background, title: "选择专属背景图片") { id in
                store.updateCard(platform.pluginId) {
                    $0.backgroundOverride = .customImage(assetID: id, focalY: 0.5)
                }
            }
            if case let .customImage(id, focalY) = appearance.backgroundOverride {
                AppearanceSlider(
                    title: "纵向取景位置",
                    value: Binding(
                        get: { focalY * 100 },
                        set: { value in
                            store.updateCard(platform.pluginId) {
                                $0.backgroundOverride = .customImage(assetID: id, focalY: value / 100)
                            }
                        }
                    ),
                    range: 0...100,
                    unit: "%"
                )
            }
        }
    }

    private var sizeSection: some View {
        Section("跨列与顺序") {
            Toggle(
                "跨两列展示",
                isOn: Binding(
                    get: { appearance.spansTwoColumns },
                    set: { value in store.updateCard(platform.pluginId) { $0.spansTwoColumns = value } }
                )
            )
            .accessibilityIdentifier("platform.card.span")
            HStack {
                Button("前移一位", systemImage: "arrow.up") {
                    store.move(
                        platform.pluginId,
                        by: -1,
                        among: orderedIDs
                    )
                }
                .buttonStyle(.borderless)
                .disabled(platform.pluginId == orderedIDs.first)
                Spacer()

                Button("后移一位", systemImage: "arrow.down") {
                    store.move(
                        platform.pluginId,
                        by: 1,
                        among: orderedIDs
                    )
                }
                .buttonStyle(.borderless)
                .disabled(platform.pluginId == orderedIDs.last)
            }
            Button("恢复此平台默认", role: .destructive) { store.resetCard(platform.pluginId) }
                .disabled(store.snapshot.cardOverrides[platform.pluginId] == nil)
        }
    }

    private func setLogoChoice(_ choice: LogoChoice) {
        logoChoice = choice
        guard choice != LogoChoice(appearance.logoMode) else { return }
        switch choice {
        case .auto: setLogo(.auto)
        case .symbol: setLogo(.symbol(name: "tv", tintHex: nil))
        case .badge:
            let glyph = PluginManagementMonogramStyle(pluginID: platform.pluginId, displayName: platform.title)
                .glyph
            setLogo(.monogramBadge(text: glyph, tintHex: nil))
        case .photo: break
        }
    }

    private var symbolBinding: Binding<String> {
        Binding(
            get: {
                if case let .symbol(name, _) = appearance.logoMode { return name }
                return "tv"
            },
            set: { setLogo(.symbol(name: $0, tintHex: tintBinding.wrappedValue)) }
        )
    }

    private var badgeBinding: Binding<String> {
        Binding(
            get: {
                if case let .monogramBadge(text, _) = appearance.logoMode { return text }
                return ""
            },
            set: { setLogo(.monogramBadge(text: $0, tintHex: tintBinding.wrappedValue)) }
        )
    }

    private var tintBinding: Binding<String?> {
        Binding(
            get: {
                switch appearance.logoMode {
                case .symbol(_, let tint), .monogramBadge(_, let tint): tint
                default: nil
                }
            },
            set: { tint in
                switch appearance.logoMode {
                case .symbol(let name, _): setLogo(.symbol(name: name, tintHex: tint))
                case .monogramBadge(let text, _): setLogo(.monogramBadge(text: text, tintHex: tint))
                default: break
                }
            }
        )
    }

    private func setLogo(_ logo: PlatformLogoMode) {
        store.updateCard(platform.pluginId) { $0.logoMode = logo }
    }
}

// MARK: - Background Swatches

private struct PlatformAppearanceBackgroundChoices: View {
    @Environment(\.displayScale) private var displayScale
    let selection: Binding<PlatformBackgroundStyle?>
    let platform: Platformdescription?
    let defaultBackground: Image

    init(
        selection: Binding<PlatformBackgroundStyle?>,
        platform: Platformdescription? = nil,
        defaultBackground: Image
    ) {
        self.selection = selection
        self.platform = platform
        self.defaultBackground = defaultBackground
    }

    @Environment(\.platformAppearanceLibrary) private var library
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PluginAvailabilityService.self) private var catalog
    @State private var globalImage: CGImage?
    @State private var loadedID: String?
    @State private var dominantColor: PlatformRGBAColor?

    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    private var options: [PlatformBackgroundStyle?] {
        let first: [PlatformBackgroundStyle?] = platform == nil ? [.defaultAsset, .systemSurface] : [nil, .defaultAsset]
        return first + [.dominantIconAura, .preset(.graphite), .preset(.ocean), .preset(.forest)]
    }

    private var tint: PlatformRGBAColor {
        if let dominantColor { return dominantColor }
        if let platform {
            let style = PluginManagementMonogramStyle(pluginID: platform.pluginId, displayName: platform.title)
            let rgb = style.backgroundRGB
            return .init(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        return .init(rgb: 0x3B6E8C)
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        let assetID = platform == nil ? nil : store.snapshot.globalBackground.assetID
        let artworkRequest = platform.map {
            ArtworkRequest(dark: colorScheme == .dark, revision: catalog.catalogRevision, liveType: $0.liveType)
        }
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(options, id: \.self) { swatch($0) }
        }
        .task(id: AssetRequest(id: assetID, revision: store.assetsRevision)) {
            guard let assetID else {
                loadedID = nil
                globalImage = nil
                return
            }
            let image = await (library?.assets ?? .shared).image(for: assetID)
            guard !Task.isCancelled else { return }
            loadedID = assetID
            globalImage = image
        }
        .task(id: artworkRequest) {
            guard let platform, let artworkRequest else { return }
            let artwork = await (library?.artwork ?? .shared).artwork(
                pluginID: platform.pluginId,
                liveType: platform.liveType,
                dark: artworkRequest.dark,
                revision: artworkRequest.revision,
                includesWordmark: false
            )
            if !Task.isCancelled { dominantColor = artwork.dominantColor }
        }
    }

    private func swatch(_ style: PlatformBackgroundStyle?) -> some View {
        let background = style ?? store.snapshot.globalBackground
        let selected = selection.wrappedValue == style
        let title = style?.appearanceTitle ?? "跟随全局"
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            selection.wrappedValue = style
        } label: {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(1.6, contentMode: .fit)
                    .background {
                        GeometryReader { geometry in
                            PlatformAppearanceBackdrop(
                                style: background,
                                image: loadedID == background.assetID ? globalImage : nil,
                                defaultBackground: defaultBackground,
                                aura: tint,
                                size: geometry.size,
                                blur: style == nil ? store.snapshot.backgroundBlurRadius : 0,
                                scrim: style == nil && store.snapshot.contrastScrimEnabled
                            )
                        }
                    }
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(.primary.opacity(0.10), lineWidth: 1 / displayScale) }
                    .padding(3)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }

                Text(title)
                    .font(selected ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(selected ? Color.primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Live Preview

public struct PlatformAppearancePreview: View {
    let platform: Platformdescription
    let idiom: PlatformDeviceIdiom
    let defaultBackground: Image
    let catalogRevision: UInt
    @Environment(\.displayScale) private var displayScale
    @State private var availableWidth: CGFloat = 0
    let width: CGFloat
    let gridWidth: CGFloat
    let gridSpacing: CGFloat
    let gridPadding: CGFloat
    @Environment(\.platformAppearanceLibrary) private var library
    private var store: PlatformAppearanceStore { library?.store ?? .shared }

    public init(
        platform: Platformdescription,
        idiom: PlatformDeviceIdiom,
        defaultBackground: Image,
        catalogRevision: UInt,
        width: CGFloat,
        gridWidth: CGFloat,
        gridSpacing: CGFloat,
        gridPadding: CGFloat
    ) {
        self.platform = platform
        self.idiom = idiom
        self.defaultBackground = defaultBackground
        self.catalogRevision = catalogRevision
        self.width = width
        self.gridWidth = gridWidth
        self.gridSpacing = gridSpacing
        self.gridPadding = gridPadding
    }

    private var stageColor: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    public var body: some View {
        let snapshot = store.snapshot
        let appearance = snapshot.appearance(for: platform.pluginId)
        let layout = PlatformAppearanceGridLayout(
            idiom: idiom,
            density: snapshot.gridDensity,
            aspect: snapshot.cardAspect,
            metrics: snapshot.metrics(for: idiom),
            spacing: gridSpacing,
            horizontalPadding: gridPadding
        )
        let stageShape = RoundedRectangle(cornerRadius: idiom == .mac ? 12 : 20, style: .continuous)
        let laneWidth = gridWidth > 0 ? gridWidth : 2 * (width + gridPadding) + gridSpacing
        let planner = layout.planner(for: laneWidth)
        let cardWidth = planner.placements(spansTwoColumns: [appearance.spansTwoColumns]).first?.width ?? width
        let height = layout.cardHeight(unitWidth: planner.unitWidth)
        let preferredWidth = appearance.spansTwoColumns && idiom != .mac ? CGFloat(320) : width
        let previewWidth = min(preferredWidth, availableWidth > 0 ? availableWidth : width)
        let scale = min(previewWidth / max(1, cardWidth), 252 / height)
        VStack(spacing: 10) {
            PlatformAppearanceCard(
                pluginID: platform.pluginId,
                title: platform.title,
                liveType: platform.liveType,
                appearance: appearance,
                snapshot: snapshot,
                idiom: idiom,
                defaultBackground: defaultBackground,
                catalogRevision: catalogRevision
            )
            .frame(width: cardWidth, height: height)
            .scaleEffect(scale)
            .frame(width: cardWidth * scale, height: height * scale)
            .accessibilityHidden(true)

            HStack(spacing: 4) {
                Text("实时预览 · \(planner.columnCount) 列 ·")
                if snapshot.metrics(for: idiom).useCustomMetrics {
                    Text("\(Int(height)) pt")
                } else {
                    Text(snapshot.cardAspect.appearanceTitle)
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
        .padding(16)
        .background(stageColor, in: stageShape)
        .overlay {
            stageShape.strokeBorder(.primary.opacity(0.06), lineWidth: 1 / displayScale)
        }
    }
}

// MARK: - Image Import

private struct AppearancePhotoPicker: View {
    let kind: PlatformAppearanceAssetCache.Kind
    let title: LocalizedStringResource
    let onImport: (String) -> Void

    @Environment(\.platformAppearanceLibrary) private var library
    @State private var importFailed = false
    #if os(iOS)
    @State private var selection: PhotosPickerItem?
    #else
    @State private var showsImporter = false
    @State private var selection: URL?
    #endif

    var body: some View {
        picker
            .disabled(selection != nil)
            .accessibilityIdentifier(
                kind == .logo ? "platform.card.importLogo" : "platform.appearance.importBackground"
            )
            .task(id: selection) { await importSelection() }
            .alert("无法导入图片", isPresented: $importFailed) {
                Button("好", role: .cancel) {}
            } message: {
                Text("请确认图片可正常打开，然后重试。")
            }
    }

    private var picker: some View {
        #if os(iOS)
        let caption = title
        return PhotosPicker(selection: $selection, matching: .images) {
            Label {
                Text(caption)
            } icon: {
                Image(systemName: "photo")
            }
        }
        #else
        Button {
            showsImporter = true
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "photo")
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                selection = url
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { importFailed = true }
            }
        }
        #endif
    }

    private func importSelection() async {
        guard let selection else { return }
        let store = library?.store ?? .shared
        let cache = library?.assets ?? .shared
        let revision = store.profileRevision
        defer {
            if !Task.isCancelled { self.selection = nil }
        }

        do {
            #if os(iOS)
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw PlatformAppearanceAssetCache.AssetError.invalidImage
            }
            let id = try await cache.importImage(data, kind: kind)
            #else
            let id = try await cache.importImage(at: selection, kind: kind)
            #endif
            try Task.checkCancellation()
            guard store.profileRevision == revision else { return }
            onImport(id)
        } catch {
            if !Task.isCancelled { importFailed = true }
        }
    }
}
#endif
