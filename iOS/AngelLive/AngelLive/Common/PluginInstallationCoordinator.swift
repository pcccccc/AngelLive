import Foundation
import Observation
import AngelLiveCore

enum PluginInstallationEntry {
    case management
    case sourceInput(String)
    case cloudSources([String])
    case sources([String])
}

struct PluginInstallationPresentation: Identifiable {
    let id = UUID()
    let entry: PluginInstallationEntry
}

/// Each page retains its own source scope when another installation page is
/// pushed or presented above it.
@MainActor
@Observable
final class PluginInstallationContext {
    var sourceURLs: [String]?
    var errorMessage: String?
    var preparationTitle: String?

    func useSources(_ urls: [String]) {
        var seen = Set<String>()
        sourceURLs = urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        errorMessage = nil
    }

    func showAllSources() {
        sourceURLs = nil
        errorMessage = nil
    }
}

/// All iOS entry points share the installation lifecycle. The root owns this
/// coordinator and the source manager, so navigation preserves batch results.
@MainActor
@Observable
final class PluginInstallationCoordinator {
    var presentation: PluginInstallationPresentation?
    private(set) var isPreparing = false
    private(set) var isInstalling = false
    private var batchSourceURLs: [String]?

    func prepare(
        _ entry: PluginInstallationEntry,
        context: PluginInstallationContext,
        manager: PluginSourceManager,
        resetsResult: Bool = true
    ) async {
        guard !isPreparing, !isInstalling, !manager.isManagementBusy else { return }
        isPreparing = true
        context.errorMessage = nil
        if resetsResult {
            switch entry {
            case .management:
                // Opening management keeps the last operation available to retry.
                break
            case .sourceInput, .cloudSources, .sources:
                manager.installBatch.clearResult()
                batchSourceURLs = nil
            }
        }
        defer {
            isPreparing = false
            context.preparationTitle = nil
        }

        switch entry {
        case .management:
            context.sourceURLs = nil
            context.preparationTitle = "正在读取插件列表…"
            await manager.fetchAllSourceIndexes()
        case .sourceInput(let input):
            context.sourceURLs = []
            context.preparationTitle = "正在读取订阅源…"
            let addedURLs = await manager.addSourceFromInput(input)
            context.sourceURLs = addedURLs
            if addedURLs.isEmpty {
                context.errorMessage = manager.errorMessage ?? "无法识别订阅源，请检查地址或兑换码。"
            } else {
                // Keep the all-source catalog valid for an underlying management
                // page while this page displays only its own source scope.
                await manager.fetchAllSourceIndexes()
            }
        case .cloudSources(let urls):
            context.useSources(urls)
            context.preparationTitle = "正在读取 iCloud 订阅源…"
            for url in context.sourceURLs ?? [] {
                manager.addSource(url)
            }
            await manager.fetchAllSourceIndexes()
        case .sources(let urls):
            context.useSources(urls)
            context.preparationTitle = "正在读取订阅源…"
            await manager.fetchAllSourceIndexes()
        }

        if !Task.isCancelled {
            await manager.refreshAvailableUpdates()
        }
    }

    func retrySource(
        _ sourceURL: String,
        context: PluginInstallationContext,
        manager: PluginSourceManager
    ) async {
        guard !isPreparing, !isInstalling, !manager.isManagementBusy else { return }
        isPreparing = true
        context.preparationTitle = "正在重新读取订阅源…"
        context.errorMessage = nil
        defer {
            isPreparing = false
            context.preparationTitle = nil
        }
        _ = await manager.refreshSource(sourceURL)
        await manager.refreshAvailableUpdates()
    }

    func install(
        pluginIds: [String],
        sourceURLs: [String]?,
        manager: PluginSourceManager,
        availability: PluginAvailabilityService
    ) async {
        await performInstall(
            pluginIds: pluginIds,
            sourceURLs: sourceURLs,
            manager: manager,
            availability: availability
        )
    }

    func retryFailed(manager: PluginSourceManager, availability: PluginAvailabilityService) async {
        await performInstall(
            pluginIds: manager.installBatch.failedPluginIds,
            sourceURLs: batchSourceURLs,
            manager: manager,
            availability: availability
        )
    }

    private func performInstall(
        pluginIds: [String],
        sourceURLs: [String]?,
        manager: PluginSourceManager,
        availability: PluginAvailabilityService
    ) async {
        guard !isPreparing, !isInstalling, !manager.isManagementBusy, !pluginIds.isEmpty else { return }
        isInstalling = true
        defer { isInstalling = false }
        batchSourceURLs = sourceURLs
        _ = await manager.installPlugins(pluginIds: pluginIds, sourceURLs: sourceURLs)
        await availability.refresh()
        // Preserve the batch's item outcomes; rebuilding remotePlugins here
        // would replace failed rows before the user can retry them.
        await manager.refreshAvailableUpdates()
    }
}
