import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI

/// SharedAssets provides a centralized access point for shared resources
/// across iOS, macOS, and tvOS platforms.
public struct SharedAssets {

    /// Access to shared colors
    public struct Colors {
        /// App accent color with automatic dark mode support
        public static var appAccent: Color {
            Color("AppAccentColor", bundle: .module)
        }

        #if canImport(UIKit)
        /// App accent color as UIColor (iOS/tvOS)
        public static var appAccentUIColor: UIColor {
            UIColor(named: "AppAccentColor", in: .module, compatibleWith: nil) ?? .systemBlue
        }
        #elseif canImport(AppKit)
        /// App accent color as NSColor (macOS)
        public static var appAccentNSColor: NSColor {
            NSColor(named: "AppAccentColor", bundle: .module) ?? .systemBlue
        }
        #endif
    }

    /// Access to shared images
    public struct Images {
        // Add your image assets here
        // Example:
        // public static var logo: Image {
        //     Image("AppLogo", bundle: .module)
        // }

        #if canImport(UIKit)
        // public static var logoUIImage: UIImage? {
        //     UIImage(named: "AppLogo", in: .module, compatibleWith: nil)
        // }
        #elseif canImport(AppKit)
        // public static var logoNSImage: NSImage? {
        //     NSImage(named: "AppLogo")?.withSymbolConfiguration(.init(bundle: .module))
        // }
        #endif
    }
}

// MARK: - Convenience Extensions

#if canImport(SwiftUI)
extension Color {
    /// Initialize a color from the SharedAssets bundle
    public static func shared(_ name: String) -> Color {
        Color(name, bundle: .module)
    }
}

extension Image {
    /// Initialize an image from the SharedAssets bundle
    public static func shared(_ name: String) -> Image {
        Image(name, bundle: .module)
    }
}
#endif
