import Foundation
import Observation

public struct PluginHomeCategoryRoute: Hashable, Sendable {
    public let pluginId: String
    public let liveType: LiveType
    public let categoryID: String
    public let parentID: String
    public let title: String
    public let icon: String
    public let biz: String?

    public init(pluginId: String, liveType: LiveType, category: LiveCategoryModel, fallbackTitle: String) {
        self.pluginId = pluginId
        self.liveType = liveType
        categoryID = category.id
        parentID = category.parentId
        title = category.title.isEmpty ? fallbackTitle : category.title
        icon = category.icon
        biz = category.biz
    }
}

@MainActor
@Observable
public final class PluginHomeCategoryModel {
    public private(set) var rooms: [LiveModel] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = true
    public private(set) var errorMessage: String?
    public let route: PluginHomeCategoryRoute

    @ObservationIgnored private var page = 1

    public init(route: PluginHomeCategoryRoute) {
        self.route = route
    }

    public func load(refresh: Bool) async {
        guard !isLoading else { return }
        if refresh {
            page = 1
            hasMore = true
            errorMessage = nil
        } else if !hasMore {
            return
        }

        guard let platform = LiveParseJSPlatformManager.platform(forPluginId: route.pluginId) else {
            errorMessage = "对应内容源已不可用。"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let context: [String: Any] = [
                "category": [
                    "id": route.categoryID,
                    "parentId": route.parentID,
                    "title": route.title,
                    "icon": route.icon,
                    "biz": route.biz ?? ""
                ]
            ]
            let fetched = try await LiveParseJSPlatformManager.getRoomList(
                platform: platform,
                id: route.categoryID,
                parentId: route.parentID,
                page: page,
                context: context
            )
            try Task.checkCancellation()
            hasMore = !fetched.isEmpty
            if refresh {
                rooms = fetched.removingDuplicates()
            } else {
                rooms = rooms.appendingUnique(contentsOf: fetched)
            }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadMore() async {
        guard !isLoading, hasMore else { return }
        page += 1
        await load(refresh: false)
        if errorMessage != nil {
            page = max(1, page - 1)
        }
    }
}
