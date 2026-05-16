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

      function normalizedKey(value) {
        return stringValue(value).trim().toLowerCase();
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

      function categoryPayload(runtime) {
        return runtime && runtime.category && typeof runtime.category === "object" ? runtime.category : {};
      }

      function categorySelection(runtime) {
        var category = categoryPayload(runtime);
        var rawId = stringValue(runtime.id || category.id).trim();
        var slug = normalizedKey(runtime.slug || runtime.biz || category.biz);

        if (!slug && rawId && rawId !== "all" && rawId !== "root" && !/^\d+$/.test(rawId)) {
          slug = normalizedKey(rawId);
        }

        if ((rawId === "all" || rawId === "root" || !rawId) && !slug) {
          return { id: "all", slug: "", rawId: rawId };
        }

        return {
          id: /^\d+$/.test(rawId) ? rawId : "",
          slug: slug,
          rawId: rawId
        };
      }

      function matchingCategory(categories, selection) {
        var list = Array.isArray(categories) ? categories : [];
        for (var i = 0; i < list.length; i += 1) {
          var item = list[i] || {};
          if (selection.id && stringValue(item.id) === selection.id) return item;
          if (selection.slug && normalizedKey(item.biz) === selection.slug) return item;
        }
        return null;
      }

      async function resolveCategorySelection(runtime) {
        var selection = categorySelection(runtime);
        if (selection.id === "all" || selection.id) return selection;
        if (!selection.slug) return selection;

        var cachedCategories = [];
        if (typeof _tw_loadCategoryCache === "function") {
          try {
            var cached = await _tw_loadCategoryCache(120);
            cachedCategories = Array.isArray(cached && cached.categories) ? cached.categories : [];
          } catch (_) {
            cachedCategories = [];
          }
        }

        var match = matchingCategory(cachedCategories, selection);
        if (!match && typeof _tw_fetchTopGames === "function") {
          var freshCategories = await _tw_fetchTopGames(100, runtime);
          match = matchingCategory(freshCategories, selection);
          if (typeof _tw_saveCategoryCache === "function" && Array.isArray(freshCategories)) {
            try {
              await _tw_saveCategoryCache(freshCategories);
            } catch (_) {}
          }
        }

        if (match && stringValue(match.id)) {
          selection.id = stringValue(match.id);
        }
        return selection;
      }

      function filterRoomsForCategory(rooms, selection) {
        var list = dedupeRooms(rooms);
        if (!selection || selection.id === "all" || !selection.id) return list;

        var filtered = list.filter(function (room) {
          return stringValue(room && room.biz) === selection.id;
        });
        return filtered.length > 0 || list.length === 0 ? filtered : list;
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
        var selection = await resolveCategorySelection(runtime);
        var categoryId = selection.id || selection.rawId || "all";
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

        return filterRoomsForCategory(pageData && pageData.items, selection);
      };

      Object.defineProperty(plugin, "__angelLiveTwitchGQLListPatch", {
        value: true,
        enumerable: false
      });
    })();
    """#
}
