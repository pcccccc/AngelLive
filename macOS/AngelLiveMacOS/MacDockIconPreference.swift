import AppKit

enum MacDockIconPreference: String, CaseIterable, Identifiable {
    static let storageKey = "macDockIconPreference"

    @MainActor
    private static var bundledIconImage: NSImage?

    case xiaoShengBiBi = "xiaoShengBB"
    // Preserve the stored value for users who explicitly selected the original.
    case classic = "primary"

    var id: Self { self }

    var title: String {
        switch self {
        case .xiaoShengBiBi: "小声逼逼（联名）"
        case .classic: "AngelLive 原版"
        }
    }

    @MainActor
    var previewImage: NSImage {
        Self.cacheBundledIconIfNeeded()

        switch self {
        case .xiaoShengBiBi:
            return Self.bundledIconImage ?? NSApp.applicationIconImage
        case .classic:
            return Self.classicIconImage
        }
    }

    @MainActor
    func apply() {
        Self.cacheBundledIconIfNeeded()

        switch self {
        case .xiaoShengBiBi:
            // nil restores the bundle icon so Icon Composer can keep supplying
            // the correct appearance-specific representation.
            NSApp.applicationIconImage = nil
        case .classic:
            NSApp.applicationIconImage = Self.classicIconImage
        }
        NSApp.dockTile.display()
    }

    @MainActor
    static func applyStoredPreference(defaults: UserDefaults = .standard) {
        let preference = defaults.string(forKey: storageKey)
            .flatMap(Self.init(rawValue:)) ?? .xiaoShengBiBi
        preference.apply()
    }

    @MainActor
    private static func cacheBundledIconIfNeeded() {
        guard bundledIconImage == nil else { return }
        bundledIconImage = NSApp.applicationIconImage.copy() as? NSImage
    }

    @MainActor
    private static var classicIconImage: NSImage {
        // The fallback is the existing rendered original icon, including its
        // rounded silhouette, for systems without named Icon Composer images.
        NSImage(named: "AngelLiveClassic")
            ?? NSImage(named: "AngelLiveClassicRuntime")
            ?? bundledIconImage
            ?? NSApp.applicationIconImage
    }
}
