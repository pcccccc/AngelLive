import Foundation
import Darwin

/// Context captured at the start of the recording, without device names or account identifiers.
enum SupportDiagnosticEnvironment {
    @MainActor
    static func snapshot() -> [String: String] {
        let settings = PlayerSettingModel()
        var values = [
            "界面模式": "FullUI",
            "时区": TimeZone.current.identifier,
            "语言": Locale.current.identifier,
            "后台音频设置": settings.enableBackgroundAudio ? "开启" : "关闭",
            "自动画中画设置": settings.enableAutoPiPOnBackground ? "开启" : "关闭"
        ]
        #if targetEnvironment(simulator)
        values["运行环境"] = "模拟器"
        values["设备型号"] = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "未取得"
        #else
        values["运行环境"] = "实体设备"
        var size = 0
        #if os(macOS)
        let modelKey = "hw.model"
        #else
        let modelKey = "hw.machine"
        #endif
        if sysctlbyname(modelKey, nil, &size, nil, 0) == 0, size > 0 {
            var bytes = [UInt8](repeating: 0, count: size)
            if sysctlbyname(modelKey, &bytes, &size, nil, 0) == 0 {
                values["设备型号"] = String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
        }
        #endif
        return values
    }
}

enum SupportDiagnosticReportSummary {
    static func lines(for report: SupportDiagnosticReport) -> [String] {
        var lines = ["", "问题描述"]
        if let description = report.userDescription, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(description)
        } else {
            lines.append("未补充：尚不知道用户看到的实际现象、预期结果及问题发生在哪一步。")
        }
        if let failure = report.failure {
            lines += ["界面错误：\(failure.title) — \(failure.message)"]
            if let detail = failure.detail { lines.append("错误详情：\(detail)") }
        }

        lines += ["", "复现前提与记录范围"]
        if let environment = report.environment {
            lines += environment.sorted { $0.key < $1.key }.map { "\($0.key)：\($0.value)" }
        } else {
            lines.append("此报告未采集设备型号与录制开始时的设置。")
        }
        let plugins = Set(report.entries.compactMap { entry -> String? in
            guard let version = entry.pluginVersion else { return nil }
            return "\(entry.pluginID) @ \(version)"
        }).sorted()
        lines.append("实际调用插件版本：\(plugins.isEmpty ? "未采集" : plugins.joined(separator: "；"))")
        lines.append("网络类型、登录状态未采集；不要据此假定与接收报告的设备相同。直播内容与临时播放地址可能随时间变化。")
        if report.schemaVersion >= 2 {
            lines.append("HTTP 文本正文保留收到的 HTML / JSON 原文及格式，仅对凭证脱敏；下方业务调用返回是插件处理后的结果，两者分别保留。")
        } else {
            lines.append("旧版报告的正文可能已被截断或重新格式化；无法从现有报告恢复丢失的原文。")
        }
        if report.actions.contains(where: { $0.action == .openedRoom && ($0.context["roomID"]?.isEmpty != false || $0.context["pluginID"]?.isEmpty != false) }) {
            lines.append("缺失：部分进入房间操作没有插件标识或房间 ID，无法据此定位同一直播间。")
        }
        if !report.limitations.isEmpty {
            lines += ["", "缺失或截断说明"] + report.limitations.map { "- \($0)" }
        }

        lines += ["", "复现操作时间线（按记录顺序）"]
        if report.actions.isEmpty { lines.append("未记录操作，无法恢复录制前的步骤。") }
        for (index, action) in report.actions.enumerated() {
            let elapsed = action.timestamp.timeIntervalSince(report.startedAt)
            lines.append("\(index + 1). [\(String(format: "+%.3fs", elapsed))] \(action.action.title)")
            for (key, value) in action.context.sorted(by: { $0.key < $1.key }) {
                lines.append("   \(contextLabel(key))：\(contextValue(key, value))")
            }
            lines.append("   operation=\(action.operationID.uuidString)")
            let related = report.entries.filter { $0.operationID == action.operationID }
            for entry in related where entry.kind == nil || entry.kind == .invocation {
                lines.append("   → \(entry.pluginID).\(entry.method)：\(status(entry))；详情 id=\(entry.id.uuidString)")
            }
            if related.isEmpty, [.openedRoom, .retriedPlayback, .searched].contains(action.action) {
                lines.append("   未记录到可严格关联的调用；不能据此判断成功或失败。")
            }
        }

        lines += ["", "失败证据索引（日志事实，不是根因判定）"]
        let failures = report.entries.filter(hasFailure)
        if failures.isEmpty { lines.append("未采集到明确失败；不代表用户没有遇到问题。") }
        for entry in failures {
            lines.append("[\(String(format: "+%.3fs", entry.timestamp.timeIntervalSince(report.startedAt)))] \(entry.pluginID).\(entry.method) id=\(entry.id.uuidString)")
            if let error = entry.errorMessage { lines.append("  \(SupportDiagnosticSanitizer.text(error, limit: 1_024))") }
            for request in entry.httpRecords where request.error != nil || request.statusCode.map({ !(200...399).contains($0) }) == true {
                lines.append("  HTTP \(request.method) \(request.url)；状态=\(request.statusCode.map(String.init) ?? "未收到")；id=\(request.id.uuidString)")
            }
            if entry.operationID == nil { lines.append("  无操作关联；不得按时间接近推断属于某个房间或步骤。") }
        }
        return lines
    }

    static func hasFailure(_ entry: SupportDiagnosticPluginEntry) -> Bool {
        entry.status == "error" || entry.exception != nil || entry.httpRecords.contains {
            $0.error != nil || $0.statusCode.map { !(200...399).contains($0) } == true
        }
    }

    static func status(_ entry: SupportDiagnosticPluginEntry) -> String {
        if entry.kind == .playerLog { return entry.status == "error" ? "错误级日志" : "日志" }
        switch entry.status {
        case "success": return "已返回（不代表界面或播放成功）"
        case "error": return "失败"
        default: return "停止录制时未完成"
        }
    }

    private static func contextLabel(_ key: String) -> String {
        let labels = [
            "pluginID": "插件", "pluginVersion": "插件版本", "platform": "平台名称",
            "roomID": "房间 ID", "anchorName": "主播", "roomTitle": "房间标题",
            "entryPoint": "入口", "lineIndex": "线路索引（从 0 开始）", "lineName": "线路",
            "qualityIndex": "清晰度索引（从 0 开始）", "qualityName": "清晰度",
            "playerKernel": "播放器内核", "silentRefresh": "静默刷新", "switchRoom": "切换房间",
            "searchKind": "搜索方式", "query": "搜索输入", "page": "页码", "selection": "选择来源"
        ]
        return labels[key] ?? key
    }

    private static func contextValue(_ key: String, _ value: String) -> String {
        if key == "selection" { return value == "automatic" ? "自动" : value == "user" ? "用户操作" : value }
        if value == "true" { return "是" }
        if value == "false" { return "否" }
        return value
    }
}
