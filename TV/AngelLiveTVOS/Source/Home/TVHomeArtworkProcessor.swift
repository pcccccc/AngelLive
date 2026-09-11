import AngelLiveDependencies
import CoreImage.CIFilterBuiltins
import os
import UIKit

/// A display-only treatment for FullUI's static hero artwork.
/// Kingfisher runs this synchronous processor on its existing background processing queue.
nonisolated struct TVHomeArtworkProcessor: ImageProcessor, Equatable {
    let pixelSize: CGSize

    // Bound each decoded result to 16 MiB of RGBA pixels. Neighbor prefetching shares
    // the app's existing memory/disk limits rather than retaining another image cache.
    private static let maximumPixelCount: CGFloat = 4_194_304
    private static let maximumDimension: CGFloat = 3_840

    // CIContext is thread-safe and Sendable; mutable CIFilters are local to each call.
    private static let context = CIContext(options: [.cacheIntermediates: false])
#if DEBUG
    private static let logger = Logger(subsystem: "AngelLive", category: "TVHomeArtwork")
#endif

    init(viewportSize: CGSize, displayScale: CGFloat) {
        // Include the existing artwork overscan without changing the request on each
        // animation frame or when Reduce Motion changes.
        let width = max(1, viewportSize.width * displayScale * 1.1)
        let height = max(1, viewportSize.height * displayScale * 1.1)
        guard width.isFinite, height.isFinite, (width * height).isFinite else {
            pixelSize = CGSize(width: 1, height: 1)
            return
        }
        let limit = min(
            1,
            Self.maximumDimension / max(width, height),
            sqrt(Self.maximumPixelCount / (width * height))
        )
        pixelSize = CGSize(width: max(1, floor(width * limit)), height: max(1, floor(height * limit)))
    }

    var identifier: String {
        "AngelLive.TVHomeArtwork.v2.quality2.\(Int(pixelSize.width))x\(Int(pixelSize.height))"
    }

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> UIImage? {
        autoreleasepool {
            guard let image = WebPProcessor.default.process(item: item, options: options) else { return nil }
            guard let cgImage = image.kf.normalized.cgImage else { return image }
            let quality = TVHomeArtworkQuality.assess(cgImage, aspectRatio: pixelSize.width / pixelSize.height)
#if DEBUG
            Self.logger.debug("quality=\(quality.decision.rawValue, privacy: .public) effective_width=\(quality.effectiveWidth) laplacian=\(quality.strongestLaplacian) detail_ratio=\(quality.detailRatio)")
#endif
            guard quality.isSuitable else { return nil }
            let input = CIImage(cgImage: cgImage)
            let scale = max(pixelSize.width / input.extent.width, pixelSize.height / input.extent.height)
            guard scale.isFinite, scale > 0 else { return image }

            let resize = CIFilter.lanczosScaleTransform()
            resize.inputImage = input
            resize.scale = Float(scale)
            resize.aspectRatio = 1
            guard let resized = resize.outputImage else { return image }

            // Match scaledToFill's centered crop; render only the viewport so tall
            // or ultrawide sources cannot produce an unbounded intermediate bitmap.
            let crop = CGRect(
                x: floor(resized.extent.midX - pixelSize.width / 2),
                y: floor(resized.extent.midY - pixelSize.height / 2),
                width: pixelSize.width,
                height: pixelSize.height
            )
            var output = resized.clampedToExtent()
            if scale > 1.05 {
                let sharpen = CIFilter.sharpenLuminance()
                sharpen.inputImage = resized.clampedToExtent()
                sharpen.sharpness = 0.25
                sharpen.radius = 1
                output = sharpen.outputImage ?? resized
            }
            let colorSpace = cgImage.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
                ?? CGColorSpace(name: CGColorSpace.sRGB)!
            guard let result = Self.context.createCGImage(
                output.cropped(to: crop),
                from: crop,
                format: .RGBA8,
                colorSpace: colorSpace
            ) else {
#if DEBUG
                Self.logger.debug("result=render_fallback input=\(cgImage.width)x\(cgImage.height) target=\(Int(pixelSize.width))x\(Int(pixelSize.height))")
#endif
                return image
            }
#if DEBUG
            Self.logger.debug("result=enhanced input=\(cgImage.width)x\(cgImage.height) output=\(result.width)x\(result.height) scale=\(scale)")
#endif
            return UIImage(cgImage: result, scale: image.scale, orientation: .up)
        }
    }
}

/// Store the processed pixels, not WebPSerializer's original-data representation.
/// WebP-aware reads also allow Kingfisher to reuse its separately cached originals.
nonisolated struct TVHomeArtworkCacheSerializer: CacheSerializer {
    static let shared = TVHomeArtworkCacheSerializer()

    func data(with image: UIImage, original: Data?) -> Data? {
        FormatIndicatedCacheSerializer.png.data(with: image, original: nil)
    }

    func image(with data: Data, options: KingfisherParsedOptionsInfo) -> UIImage? {
        WebPProcessor.default.process(item: .data(data), options: options)
    }
}
