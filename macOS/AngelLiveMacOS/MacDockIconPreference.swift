import AppKit

enum MacDockIconPreference: String, CaseIterable, Identifiable {
    static let storageKey = "macDockIconPreference"

    @MainActor
    private static var primaryIconImage: NSImage?

    case primary
    case xiaoShengBiBi = "xiaoShengBB"

    var id: Self { self }

    var title: String {
        switch self {
        case .primary: "默认"
        case .xiaoShengBiBi: "小声逼逼"
        }
    }

    @MainActor
    var previewImage: NSImage {
        Self.cachePrimaryIconIfNeeded()

        switch self {
        case .primary:
            return Self.primaryIconImage ?? NSApp.applicationIconImage
        case .xiaoShengBiBi:
            return Self.alternateIconImage
        }
    }

    @MainActor
    func apply() {
        Self.cachePrimaryIconIfNeeded()

        switch self {
        case .primary:
            // nil restores the bundle icon so Icon Composer can keep supplying
            // the correct appearance-specific representation.
            NSApp.applicationIconImage = nil
        case .xiaoShengBiBi:
            NSApp.applicationIconImage = Self.alternateIconImage
        }
        NSApp.dockTile.display()
    }

    @MainActor
    static func applyStoredPreference(defaults: UserDefaults = .standard) {
        let preference = defaults.string(forKey: storageKey)
            .flatMap(Self.init(rawValue:)) ?? .primary
        preference.apply()
    }

    @MainActor
    private static func cachePrimaryIconIfNeeded() {
        guard primaryIconImage == nil else { return }
        primaryIconImage = NSApp.applicationIconImage.copy() as? NSImage
    }

    @MainActor
    private static var alternateIconImage: NSImage {
        if let composedIcon = NSImage(named: "XiaoShengBB") {
            return composedIcon
        }

        guard let source = NSImage(named: "XiaoShengBBRuntime") else {
            return primaryIconImage ?? NSApp.applicationIconImage
        }

        // Compatibility fallback for a toolchain that cannot expose the compiled
        // Icon Composer rendition through NSImage(named:).
        let size = source.size
        let output = NSImage(size: size)
        output.lockFocus()
        defer { output.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        let bounds = NSRect(origin: .zero, size: size)
        let radius = min(size.width, size.height) * 0.2237
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).addClip()
        source.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        return output
    }
}
