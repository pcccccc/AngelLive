import AppKit

enum MacDockIconPreference: String, CaseIterable, Identifiable {
    static let storageKey = "macDockIconPreference"

    @MainActor
    private static var bundledIconImage: NSImage?

    // Preserve the stored value for users who explicitly selected the original.
    case classic = "primary"
    case xiaoShengBiBi = "xiaoShengBB"

    var id: Self { self }

    var title: String {
        switch self {
        case .classic: "AngelLive 原版"
        case .xiaoShengBiBi: "小声逼逼（联名）"
        }
    }

    @MainActor
    var previewImage: NSImage {
        Self.cacheBundledIconIfNeeded()

        switch self {
        case .classic:
            return NSImage(named: "AngelLiveClassicRuntime") ?? Self.bundledIconImage ?? NSApp.applicationIconImage
        case .xiaoShengBiBi:
            return Self.collaborationIconImage ?? Self.bundledIconImage ?? NSApp.applicationIconImage
        }
    }

    @MainActor
    func apply() {
        Self.cacheBundledIconIfNeeded()

        switch self {
        case .classic:
            // nil restores the bundle icon so Icon Composer can keep supplying
            // the correct appearance-specific representation.
            NSApp.applicationIconImage = nil
        case .xiaoShengBiBi:
            NSApp.applicationIconImage = Self.collaborationIconImage
        }
        NSApp.dockTile.display()
    }

    @MainActor
    static func applyStoredPreference(defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: storageKey) == Self.xiaoShengBiBi.rawValue else { return }
        Self.xiaoShengBiBi.apply()
    }

    @MainActor
    private static func cacheBundledIconIfNeeded() {
        guard bundledIconImage == nil else { return }
        bundledIconImage = NSApp.applicationIconImage.copy() as? NSImage
    }

    @MainActor
    private static var collaborationIconImage: NSImage? {
        if let composedIcon = NSImage(named: "XiaoShengBB") {
            return composedIcon
        }

        guard let source = NSImage(named: "XiaoShengBBRuntime") else { return nil }

        // Keep the rounded silhouette when AppKit cannot load the named Icon Composer image.
        let size = source.size
        return NSImage(size: size, flipped: false) { bounds in
            let radius = min(size.width, size.height) * 0.2237
            NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
            source.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}
