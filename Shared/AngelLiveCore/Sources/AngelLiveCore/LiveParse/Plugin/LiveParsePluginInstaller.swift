import Foundation
import SWCompression

public enum LiveParsePluginInstaller {
    public static func install(zipData: Data, storage: LiveParsePluginStorage) throws -> LiveParsePluginManifest {
        try storage.ensureDirectories()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveParsePluginInstall", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let manifest = try extractPlugin(zipData: zipData, to: tempRoot)
        try placeExtractedPlugin(at: tempRoot, manifest: manifest, storage: storage)
        return manifest
    }

    static func extractPlugin(zipData: Data, to directory: URL) throws -> LiveParsePluginManifest {
        try extract(zipData: zipData, to: directory)
        let manifestURL = directory.appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw LiveParsePluginError.invalidManifest("manifest.json not found")
        }
        return try LiveParsePluginManifest.load(from: manifestURL)
    }

    static func placeExtractedPlugin(
        at directory: URL,
        manifest: LiveParsePluginManifest,
        storage: LiveParsePluginStorage,
        replacingExisting: Bool = true
    ) throws {
        let destination = storage.pluginVersionDirectory(pluginId: manifest.pluginId, version: manifest.version)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if replacingExisting, FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: directory, to: destination)
    }

    public static func extract(zipData: Data, to destinationDirectory: URL) throws {
        let entries = try ZipContainer.open(container: zipData)

        for entry in entries {
            let relativePath = try sanitize(relativePath: entry.info.name)
            let targetURL = destinationDirectory.appendingPathComponent(relativePath, isDirectory: entry.info.type == .directory)

            if entry.info.type == .directory {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
                continue
            }

            guard let data = entry.data else {
                continue
            }
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: targetURL, options: [.atomic])
        }
    }

    private static func sanitize(relativePath: String) throws -> String {
        // 兼容 Windows 风格的反斜杠路径分隔符
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") {
            throw LiveParsePluginError.zipSlipDetected(relativePath)
        }
        let components = normalized.split(separator: "/").map(String.init)
        if components.contains("..") {
            throw LiveParsePluginError.zipSlipDetected(relativePath)
        }
        return components.joined(separator: "/")
    }
}

