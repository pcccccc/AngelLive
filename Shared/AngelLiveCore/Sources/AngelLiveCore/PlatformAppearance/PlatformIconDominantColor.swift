import CoreGraphics
import os

public enum PlatformIconDominantColor {
    private struct Sample: Sendable {
        let color: PlatformRGBAColor?
    }

    // The lock protects only the bounded dictionary. Pixel work happens outside the lock.
    private static let cache = OSAllocatedUnfairLock(initialState: [String: Sample]())

    public static func extract(from cgImage: CGImage, cacheKey: String? = nil) -> PlatformRGBAColor? {
        if let cacheKey, let sample = cache.withLock({ $0[cacheKey] }) { return sample.color }
        let color = sample(cgImage)
        if let cacheKey {
            cache.withLock {
                if $0.count >= 256 { $0.removeAll(keepingCapacity: true) }
                $0[cacheKey] = Sample(color: color)
            }
        }
        return color
    }

    private static func sample(_ image: CGImage) -> PlatformRGBAColor? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: base, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: side * 4, space: colorSpace,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        var counts: [Int: Int] = [:]
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha >= 40 else { continue }
            let red = min(255, Int(pixels[offset]) * 255 / alpha)
            let green = min(255, Int(pixels[offset + 1]) * 255 / alpha)
            let blue = min(255, Int(pixels[offset + 2]) * 255 / alpha)
            let high = max(red, green, blue)
            let low = min(red, green, blue)
            guard high > 0, Double(high - low) / Double(high) >= 0.18 else { continue }
            let key = (red / 16) << 8 | (green / 16) << 4 | (blue / 16)
            counts[key, default: 0] += 1
        }
        guard let best = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else { return nil }
        return .init(red: (Double(best >> 8) + 0.5) / 16,
                     green: (Double((best >> 4) & 15) + 0.5) / 16,
                     blue: (Double(best & 15) + 0.5) / 16)
    }
}
