import Foundation

enum LiveParsePluginCompatibilityPatch {
    static func apply(to runtime: JSRuntime, manifest: LiveParsePluginManifest) async throws {
        guard let script = script(for: manifest) else {
            return
        }
        try await runtime.evaluate(script: script)
    }

    static func script(for manifest: LiveParsePluginManifest) -> String? {
        switch (manifest.pluginId, manifest.version) {
        case ("twitch", "1.0.31"):
            return twitch1031GQLListPatch
        default:
            return nil
        }
    }

    // Twitch 1.0.31 declares a website-GQL rewrite, but its exported category
    // and room-list methods still call the Helix token-server path. That server
    // can return payloads without clientId/accessToken, which blocks the whole
    // platform page before users reach playback. Reuse the GQL helpers already
    // bundled inside the plugin and keep the patch exact-version scoped so a
    // rebuilt upstream plugin is not overridden.
    private static let twitch1031GQLListPatch = #"""
    (function () {
      var plugin = globalThis.LiveParsePlugin;
      if (!plugin || plugin.__angelLiveTwitchGQLListPatch === true) return;

      var originalGetCategories =
        typeof plugin.getCategories === "function" ? plugin.getCategories.bind(plugin) : null;
      var originalGetRooms =
        typeof plugin.getRooms === "function" ? plugin.getRooms.bind(plugin) : null;

      function stringValue(value) {
        return value === undefined || value === null ? "" : String(value);
      }

      function intValue(value, fallback) {
        var parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : fallback;
      }

      function runtimePayload(payload) {
        return payload && typeof payload === "object" ? Object.assign({}, payload) : {};
      }

      function roomPageSize(value) {
        if (typeof _tw_roomPageSize === "function") return _tw_roomPageSize(value);
        return Math.max(1, Math.min(100, intValue(value, 20)));
      }

      function dedupeRooms(rooms) {
        if (typeof _tw_dedupeRooms === "function") return _tw_dedupeRooms(rooms);
        var seen = {};
        return (Array.isArray(rooms) ? rooms : []).filter(function (room) {
          var key = stringValue(room && (room.roomId || room.userId || room.userName));
          if (!key || seen[key]) return false;
          seen[key] = true;
          return true;
        });
      }

      function buildCategoryTree(categories) {
        var safeCategories = Array.isArray(categories) ? categories : [];
        return [
          {
            id: "root",
            title: "Twitch",
            icon: stringValue(safeCategories[0] && safeCategories[0].icon),
            biz: "",
            subList: [
              {
                id: "all",
                parentId: "root",
                title: "全部直播",
                icon: "",
                biz: ""
              }
            ].concat(
              safeCategories.map(function (item) {
                return {
                  id: stringValue(item && item.id),
                  parentId: "root",
                  title: stringValue(item && item.title),
                  icon: stringValue(item && item.icon),
                  biz: stringValue(item && item.biz)
                };
              })
            )
          }
        ];
      }

      plugin.getCategories = async function (payload) {
        var runtime = runtimePayload(payload);
        var cached = null;

        if (typeof _tw_loadCategoryCache === "function") {
          try {
            cached = await _tw_loadCategoryCache(120);
          } catch (_) {
            cached = null;
          }
        }

        if (cached && cached.fresh && Array.isArray(cached.categories) && cached.categories.length > 0) {
          return buildCategoryTree(cached.categories);
        }

        if (typeof _tw_fetchTopGames !== "function") {
          if (originalGetCategories) return await originalGetCategories(payload);
          return buildCategoryTree([]);
        }

        try {
          var categories = await _tw_fetchTopGames(100, runtime);
          if (typeof _tw_saveCategoryCache === "function") {
            try {
              await _tw_saveCategoryCache(categories);
            } catch (_) {}
          }
          return buildCategoryTree(categories);
        } catch (error) {
          if (cached && Array.isArray(cached.categories) && cached.categories.length > 0) {
            return buildCategoryTree(cached.categories);
          }
          throw error;
        }
      };

      plugin.getRooms = async function (payload) {
        var runtime = runtimePayload(payload);
        var categoryId = stringValue(runtime.id) === "root" ? "all" : stringValue(runtime.id) || "all";
        var page = Math.max(1, intValue(runtime.page, 1));
        var pageSize = roomPageSize(runtime.pageSize);
        var pageData = null;

        if (categoryId === "all") {
          if (typeof _tw_fetchAllStreamsPage !== "function") {
            return originalGetRooms ? await originalGetRooms(payload) : [];
          }
          pageData = await _tw_fetchAllStreamsPage(page, pageSize, runtime);
        } else {
          if (typeof _tw_fetchCategoryStreamsPage !== "function") {
            return originalGetRooms ? await originalGetRooms(payload) : [];
          }
          pageData = await _tw_fetchCategoryStreamsPage(categoryId, page, pageSize, runtime);
        }

        return dedupeRooms(pageData && pageData.items);
      };

      Object.defineProperty(plugin, "__angelLiveTwitchGQLListPatch", {
        value: true,
        enumerable: false
      });
    })();
    """#
}
