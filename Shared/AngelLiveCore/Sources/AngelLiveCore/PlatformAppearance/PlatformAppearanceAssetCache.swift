import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor PlatformAppearanceAssetCache {
    public static let shared = PlatformAppearanceAssetCache(
        directory: PlatformAppearanceStore.defaultDirectory.appendingPathComponent("PlatformAppearanceAssets", isDirectory: true)
    )

    public enum Kind: Sendable {
        case logo, background

        var maximumDimension: Int { self == .logo ? 512 : 1_600 }
    }

    public enum AssetError: Error {
        case invalidImage
        case exceedsSizeLimit
        case invalidIdentifier
        case integrityMismatch
    }

    static let maximumBytes = 1_500_000
    private let directory: URL
    private let decodedImages = NSCache<NSString, CGImage>()

    public init(directory: URL) {
        self.directory = directory
        decodedImages.totalCostLimit = 24 * 1024 * 1024
    }

    public func importImage(_ data: Data, kind: Kind) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { throw AssetError.invalidImage }
        return try importImage(source, kind: kind)
    }

    public func importImage(at url: URL, kind: Kind) throws -> String {
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityAccess { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else { throw AssetError.invalidImage }
        return try importImage(source, kind: kind)
    }

    private func importImage(_ source: CGImageSource, kind: Kind) throws -> String {
        var dimension = kind.maximumDimension
        while true {
            try Task.checkCancellation()
            guard let image = Self.thumbnail(source, dimension: dimension) else { throw AssetError.invalidImage }
            let hasAlpha = [.premultipliedFirst, .premultipliedLast, .first, .last, .alphaOnly].contains(image.alphaInfo)
            let format: UTType = kind == .logo || hasAlpha ? .png : .jpeg
            let data = try Self.encode(image, as: format)
            if data.count <= Self.maximumBytes {
                let id = Self.assetID(for: data)
                try write(data, id: id)
                return id
            }
            guard dimension > 128 else { throw AssetError.exceedsSizeLimit }
            dimension = max(128, dimension * 3 / 4)
        }
    }

    func storeDownloaded(_ data: Data, assetID: String) throws {
        try validate(data, assetID: assetID)
        try write(data, id: assetID)
    }

    func data(for assetID: String) throws -> Data? {
        guard let url = fileURL(for: assetID) else { throw AssetError.invalidIdentifier }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Self.readBoundedFile(url)
        guard Self.assetID(for: data) == assetID else { throw AssetError.integrityMismatch }
        return data
    }

    public func image(for assetID: String) -> CGImage? {
        let key = assetID as NSString
        if let image = decodedImages.object(forKey: key) { return image }
        guard let data = try? data(for: assetID),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = Self.thumbnail(source, dimension: Kind.background.maximumDimension) else { return nil }
        decodedImages.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    /// Keep unreferenced files for a grace period so an import and its snapshot update can overlap cleanup.
    func removeOrphans(retaining assetIDs: Set<String>, olderThan cutoff: Date) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        for url in urls where Self.isValidID(url.lastPathComponent) && !assetIDs.contains(url.lastPathComponent) {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, modified < cutoff {
                try FileManager.default.removeItem(at: url)
                decodedImages.removeObject(forKey: url.lastPathComponent as NSString)
            }
        }
    }

    private func validate(_ data: Data, assetID: String) throws {
        guard Self.isValidID(assetID) else { throw AssetError.invalidIdentifier }
        guard data.count <= Self.maximumBytes else { throw AssetError.exceedsSizeLimit }
        guard Self.assetID(for: data) == assetID else { throw AssetError.integrityMismatch }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let format = CGImageSourceGetType(source) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier].contains(format),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...Kind.background.maximumDimension).contains(width),
              (1...Kind.background.maximumDimension).contains(height),
              Self.thumbnail(source, dimension: Kind.background.maximumDimension) != nil
        else { throw AssetError.invalidImage }
    }

    private func write(_ data: Data, id: String) throws {
        guard let url = fileURL(for: id) else { throw AssetError.invalidIdentifier }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func fileURL(for assetID: String) -> URL? {
        guard Self.isValidID(assetID) else { return nil }
        return directory.appendingPathComponent(assetID, isDirectory: false)
    }

    static func isValidID(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func digest(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func assetID(for data: Data) -> String {
        String(digest(for: data).prefix(32))
    }

    static func readBoundedFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= maximumBytes else { throw AssetError.exceedsSizeLimit }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw AssetError.exceedsSizeLimit }
        return data
    }

    private static func thumbnail(_ source: CGImageSource, dimension: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension
        ] as CFDictionary)
    }

    private static func encode(_ image: CGImage, as format: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.identifier as CFString, 1, nil)
        else { throw AssetError.invalidImage }
        let properties: CFDictionary? = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
            : nil
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw AssetError.invalidImage }
        return data as Data
    }
}
