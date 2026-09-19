import Foundation

/// Builds the public, reproducible context attached to a support diagnostic action.
///
/// The context intentionally excludes credentials, stream URLs, share input, and any
/// other private transport data. Plugin versions are not inferred from the installed
/// catalog because that catalog can differ from the version selected by the runtime.
public enum SupportDiagnosticActionContext {
    public static func room(
        _ room: LiveModel,
        additional: [String: String] = [:]
    ) -> [String: String] {
        var context: [String: String] = [:]
        add(room.roomId, for: "roomID", to: &context)
        add(room.userName, for: "anchorName", to: &context)
        add(room.roomTitle, for: "roomTitle", to: &context)

        if let platform = SandboxPluginCatalog.platform(for: room.liveType) {
            add(platform.pluginId, for: "pluginID", to: &context)
            add(platform.displayName, for: "platform", to: &context)
        }

        return merging(context, additional: additional)
    }

    public static func platform(
        _ platform: LiveParseJSPlatform,
        additional: [String: String] = [:]
    ) -> [String: String] {
        merging([
            "pluginID": platform.pluginId,
            "platform": platform.displayName,
        ], additional: additional)
    }

    public static func search(
        keyword: String,
        page: Int? = nil,
        additional: [String: String] = [:]
    ) -> [String: String] {
        var context: [String: String] = [:]
        context["query"] = SupportDiagnosticSanitizer.text(keyword)
        if let page {
            context["page"] = String(page)
        }
        return merging(context, additional: additional)
    }

    public static func shareSearch(
        page: Int? = nil,
        additional: [String: String] = [:]
    ) -> [String: String] {
        var context: [String: String] = ["searchKind": "share"]
        if let page {
            context["page"] = String(page)
        }
        return merging(context, additional: additional)
    }

    public static func selection(
        room: LiveModel,
        lineIndex: Int,
        lineName: String?,
        qualityIndex: Int,
        qualityName: String?,
        playerKernel: String?,
        additional: [String: String] = [:]
    ) -> [String: String] {
        var context = Self.room(room)
        context["lineIndex"] = String(lineIndex)
        context["qualityIndex"] = String(qualityIndex)
        add(lineName, for: "lineName", to: &context)
        add(qualityName, for: "qualityName", to: &context)
        add(playerKernel, for: "playerKernel", to: &context)
        return merging(context, additional: additional)
    }

    private static func merging(
        _ context: [String: String],
        additional: [String: String]
    ) -> [String: String] {
        var merged = context
        for (key, value) in additional {
            add(value, for: key, to: &merged)
        }
        return merged
    }

    private static func add(_ value: String?, for key: String, to context: inout [String: String]) {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return }
        context[key] = value
    }

}
