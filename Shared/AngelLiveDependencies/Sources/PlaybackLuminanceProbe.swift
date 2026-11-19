#if canImport(KSPlayer)
import AVFoundation
import CoreImage
import CoreVideo
import KSPlayer
import Metal

@MainActor
public final class PlaybackLuminanceProbe {
    private weak var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    public func frame(from player: (any MediaPlayerProtocol)?) -> (any PixelBufferProtocol)? {
        if let avPlayer = player as? KSAVPlayer, let currentItem = avPlayer.player.currentItem,
           currentItem.status == .readyToPlay {
            if currentItem !== item {
                detach()
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ])
                currentItem.add(output)
                item = currentItem
                self.output = output
            }
            guard let output else { return nil }
            return output.copyPixelBuffer(forItemTime: avPlayer.player.currentTime(), itemTimeForDisplay: nil)
        }

        detach()
        return (player?.view as? any VideoOutput)?.pixelBuffer
    }

    public func detach() {
        if let item, let output { item.remove(output) }
        item = nil
        output = nil
    }

    public func brightCells(in frame: any PixelBufferProtocol) -> Int? {
        if let buffer = frame.cvPixelBuffer {
            let format = CVPixelBufferGetPixelFormatType(buffer)
            let depth: Int
            let fullRange: Bool
            switch format {
            case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
                (depth, fullRange) = (8, true)
            case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
                (depth, fullRange) = (8, false)
            case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
                (depth, fullRange) = (10, true)
            case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
                (depth, fullRange) = (10, false)
            case kCVPixelFormatType_32BGRA:
                return packedBGRCells(in: buffer)
            default:
                return nil
            }
            guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }

            return brightCells(
                base: UnsafeRawPointer(base), width: CVPixelBufferGetWidthOfPlane(buffer, 0),
                height: CVPixelBufferGetHeightOfPlane(buffer, 0), stride: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
                sampleSize: depth == 8 ? 1 : 2,
                cutoff: luminanceCutoff(depth: depth, fullRange: fullRange) << (depth == 8 ? 0 : 6)
            )
        }

        // Software frames keep their luma plane in CPU-visible, buffer-backed
        // textures. Read that storage without allocating a converted frame.
        guard frame.planeCount > 1, (8...16).contains(frame.bitDepth) else { return nil }
        let sampleSize = frame.bitDepth > 8 ? 2 : 1
        guard let luma = frame.textures().first, luma.width == frame.width,
              luma.pixelFormat == (sampleSize == 1 ? .r8Unorm : .r16Unorm),
              let storage = luma.buffer, storage.storageMode == .shared else { return nil }
        return brightCells(
            base: UnsafeRawPointer(storage.contents().advanced(by: luma.bufferOffset)),
            width: luma.width, height: luma.height, stride: luma.bufferBytesPerRow,
            sampleSize: sampleSize,
            cutoff: luminanceCutoff(depth: Int(frame.bitDepth), fullRange: frame.isFullRangeVideo) << frame.leftShift
        )
    }

    private func packedBGRCells(in buffer: CVPixelBuffer) -> Int? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, stride >= width * 4 else { return nil }

        var bright = 0
        for row in 0..<6 {
            let y = (2 * row + 1) * height / 12
            for column in 0..<8 {
                let x = (2 * column + 1) * width / 16
                let offset = y * stride + x * 4
                if isBright(red: base[offset + 2], green: base[offset + 1], blue: base[offset]) {
                    bright += 1
                }
            }
        }
        return bright
    }

    public func convertedBrightCells(in frame: any PixelBufferProtocol) -> Int? {
        if let image = frame.cgImage(), let bright = rasterizedBrightCells(in: image) { return bright }

        guard let buffer = frame.cvPixelBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)

        let extent = image.extent
        guard extent.width > 0, extent.height > 0, !extent.isInfinite else { return nil }
        // Packed and compressed buffers need color conversion. Render only a
        // tiny grid and release the image at the end of this sample.
        let width = 8
        let height = 6
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / extent.width, y: CGFloat(height) / extent.height))
        var samples = [UInt8](repeating: 0, count: width * height * 4)
        samples.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            Self.imageContext.render(
                scaled, toBitmap: base, rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        }

        var opaqueCells = 0
        var brightCells = 0
        for offset in stride(from: 0, to: samples.count, by: 4) where samples[offset + 3] > 0 {
            opaqueCells += 1
            if isBright(red: samples[offset], green: samples[offset + 1], blue: samples[offset + 2]) { brightCells += 1 }
        }
        return opaqueCells > 0 ? brightCells : nil
    }

    private func rasterizedBrightCells(in image: CGImage) -> Int? {
        let width = 8
        let height = 6
        var samples = [UInt8](repeating: 0, count: width * height)
        let didRender = samples.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return didRender ? samples.count { $0 >= 204 } : nil
    }

    private func isBright(red: UInt8, green: UInt8, blue: UInt8) -> Bool {
        0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue) >= 204
    }

    #if DEBUG
    public func formatDescription(for frame: (any PixelBufferProtocol)?) -> String {
        guard let frame else { return "无" }
        if let buffer = frame.cvPixelBuffer {
            return String(format: "CV:%08x/%d", CVPixelBufferGetPixelFormatType(buffer), CVPixelBufferGetPlaneCount(buffer))
        }
        return "软件/\(frame.planeCount)/\(frame.bitDepth)"
    }
    #endif

    private func luminanceCutoff(depth: Int, fullRange: Bool) -> UInt16 {
        if fullRange {
            let maximum = (1 << depth) - 1
            return UInt16(0.8 * Double(maximum))
        }
        return UInt16(191 << (depth - 8))
    }

    private func brightCells(
        base: UnsafeRawPointer, width: Int, height: Int, stride: Int, sampleSize: Int, cutoff: UInt16
    ) -> Int? {
        guard width > 0, height > 0, stride >= width * sampleSize else { return nil }
        var bright = 0
        for row in 0..<6 {
            let y = (2 * row + 1) * height / 12
            for column in 0..<8 {
                let x = (2 * column + 1) * width / 16
                let offset = y * stride + x * sampleSize
                let value = sampleSize == 1
                    ? UInt16(base.load(fromByteOffset: offset, as: UInt8.self))
                    : base.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
                if value >= cutoff {
                    bright += 1
                }
            }
        }
        return bright
    }
}
#endif
