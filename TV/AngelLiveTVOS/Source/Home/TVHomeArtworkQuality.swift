import CoreGraphics
import Foundation

/// Conservative display suitability for a full-width TV hero, measured before enhancement.
/// This is a heuristic, not a semantic judgement of the image or its subject.
nonisolated enum TVHomeArtworkQuality {
    enum Decision: String, Sendable {
        case suitable, insufficientResolution, blurred, unmeasurable
    }

    struct Assessment: Sendable {
        let decision: Decision
        let effectiveWidth: Double
        let strongestLaplacian: Double
        let detailRatio: Double

        var isSuitable: Bool { decision == .suitable || decision == .unmeasurable }
    }

    static func assess(_ image: CGImage, aspectRatio: Double) -> Assessment {
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16.0 / 9.0
        let cropWidth = min(Double(image.width), Double(image.height) * aspect)
        let cropHeight = cropWidth / aspect
        func result(_ decision: Decision, laplacian: Double = 0, ratio: Double = 0) -> Assessment {
            Assessment(decision: decision, effectiveWidth: cropWidth,
                       strongestLaplacian: laplacian, detailRatio: ratio)
        }

        // Count only pixels surviving the centered fill crop. A tall or ultrawide
        // source must not pass solely because its longest side has many pixels.
        guard cropWidth >= 640 else { return result(.insufficientResolution) }
        let crop = CGRect(x: (Double(image.width) - cropWidth) / 2,
                          y: (Double(image.height) - cropHeight) / 2,
                          width: cropWidth, height: cropHeight).integral
        guard let cropped = image.cropping(to: crop) else { return result(.unmeasurable) }
        let width = 512
        let height = max(8, min(512, Int((Double(width) / aspect).rounded())))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return result(.unmeasurable) }

        // Use the sharpest content tile so a plain background or shallow depth of
        // field does not dominate a genuinely sharp logo, face, or text region.
        var strongestLaplacian = 0.0
        var strongestRatio = 0.0
        var hasMeasurableContent = false
        for row in 0..<3 {
            for column in 0..<4 {
                var sum = 0.0
                var squared = 0.0
                var gradient = 0.0
                var count = 0.0
                for y in max(1, row * height / 3)..<min(height - 1, (row + 1) * height / 3) {
                    for x in max(1, column * width / 4)..<min(width - 1, (column + 1) * width / 4) {
                        let index = y * width + x
                        let center = Double(pixels[index])
                        let left = Double(pixels[index - 1]), right = Double(pixels[index + 1])
                        let up = Double(pixels[index - width]), down = Double(pixels[index + width])
                        let laplacian = left + right + up + down - 4 * center
                        sum += laplacian
                        squared += laplacian * laplacian
                        gradient += ((right - left) * (right - left) + (down - up) * (down - up)) / 4
                        count += 1
                    }
                }
                guard count > 0 else { continue }
                let variance = max(0, squared / count - (sum / count) * (sum / count))
                let edgeEnergy = gradient / count
                // Flat or very gradual regions provide no reliable blur evidence.
                guard edgeEnergy > 1 else { continue }
                hasMeasurableContent = true
                strongestLaplacian = max(strongestLaplacian, variance)
                strongestRatio = max(strongestRatio, variance / edgeEnergy)
            }
        }
        let blurred = hasMeasurableContent && strongestLaplacian < 35 && strongestRatio < 0.35
        return result(blurred ? .blurred : .suitable,
                      laplacian: strongestLaplacian, ratio: strongestRatio)
    }
}
