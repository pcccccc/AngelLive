import Foundation

public actor LiveParseLoadedPlugin {
    public nonisolated let manifest: LiveParsePluginManifest
    public nonisolated let rootDirectory: URL
    public nonisolated let location: Location
    public nonisolated let runtime: JSRuntime
    private var isLoaded = false

    public enum Location: String, Sendable {
        case builtIn
        case sandbox
    }

    public init(manifest: LiveParsePluginManifest, rootDirectory: URL, location: Location, runtime: JSRuntime) {
        self.manifest = manifest
        self.rootDirectory = rootDirectory
        self.location = location
        self.runtime = runtime
    }

    public var entryFileURL: URL {
        rootDirectory.appendingPathComponent(manifest.entry, isDirectory: false)
    }

    public func load() async throws {
        if isLoaded {
            return
        }

        // 预加载依赖脚本
        if let preloadScripts = manifest.preloadScripts {
            for scriptName in preloadScripts {
                let scriptURL = rootDirectory.appendingPathComponent(scriptName, isDirectory: false)
                if FileManager.default.fileExists(atPath: scriptURL.path) {
                    try await runtime.evaluate(contentsOf: scriptURL)
                } else {
                    throw LiveParsePluginError.missingEntryFile("preload: \(scriptName)")
                }
            }
        }

        guard FileManager.default.fileExists(atPath: entryFileURL.path) else {
            throw LiveParsePluginError.missingEntryFile(manifest.entry)
        }

        try await runtime.evaluate(contentsOf: entryFileURL)
        let actual = try await runtime.pluginAPIVersion()
        if actual != JSRuntime.supportedAPIVersion {
            throw LiveParsePluginError.incompatibleAPIVersion(expected: JSRuntime.supportedAPIVersion, actual: actual)
        }
        try await LiveParsePluginCompatibilityPatch.apply(to: runtime, manifest: manifest)
        isLoaded = true
    }
}
