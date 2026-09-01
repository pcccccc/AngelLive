//
//  PluginConsoleView.swift
//  AngelLiveCore
//
//  开发者控制台主视图(跨端复用):头部 + 搜索 + 筛选 + 日志列表 + 详情 sheet。
//  各端的"容器"(iOS 浮动球+底部 sheet / macOS NSWindow / tvOS 设置页 push)在各端自己实现,
//  内容统一从这里走。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, *)
public struct PluginConsoleView: View {
    @Bindable private var service: PluginConsoleService
    private let onClose: (() -> Void)?

    @State private var searchText = ""
    @State private var selectedStatus: ConsoleStatusFilter = .all
    @State private var selectedTag: String? = nil
    @FocusState private var isSearchFocused: Bool

    /// - Parameters:
    ///   - service: 共享 PluginConsoleService 实例(通常传 `.shared`)。
    ///   - onClose: 关闭按钮回调。传 nil 表示当前容器自己有关闭手段(如 macOS NSWindow 标题栏),
    ///     这种情况下视图不显示关闭按钮。
    public init(
        service: PluginConsoleService = .shared,
        onClose: (() -> Void)? = nil
    ) {
        self.service = service
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if !service.entries.isEmpty {
                searchBar
                filterChipsRow
            }
            if service.entries.isEmpty {
                emptyState
            } else if filteredEntries.isEmpty {
                noMatchState
            } else {
                entryList
            }
        }
    }

    // MARK: - 派生数据

    /// 当前过滤后的可见 entry。搜索匹配 tag / method / request / response / errorMessage 全字段。
    private var filteredEntries: [PluginConsoleEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return service.entries.filter { entry in
            switch selectedStatus {
            case .all: break
            case .loading: if entry.status != .loading { return false }
            case .success: if entry.status != .success { return false }
            case .error:   if entry.status != .error   { return false }
            }
            if let selectedTag, entry.tag != selectedTag {
                return false
            }
            if !query.isEmpty {
                let haystacks: [String?] = [
                    entry.tag,
                    entry.method,
                    entry.requestBody,
                    entry.responseBody,
                    entry.errorMessage
                ]
                let matched = haystacks.contains { ($0 ?? "").lowercased().contains(query) }
                if !matched { return false }
            }
            return true
        }
    }

    /// 已经出现过的 tag 集合,保留出现顺序作为筛选 chip 列表。
    private var availableTags: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for entry in service.entries where !seen.contains(entry.tag) {
            seen.insert(entry.tag)
            ordered.append(entry.tag)
        }
        return ordered
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 16))
                .foregroundStyle(.red)

            Text("插件控制台")
                .font(.system(.headline, design: .rounded))

            Spacer()

            if !service.entries.isEmpty {
                headerIconButton(systemName: "trash") {
                    withAnimation { service.clear() }
                }
            }

            if let onClose {
                headerIconButton(systemName: "xmark", isSmall: true, action: onClose)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func headerIconButton(systemName: String, isSmall: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: isSmall ? 10 : 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("搜索 tag / method / 内容", text: $searchText)
                .font(.system(.subheadline, design: .rounded))
                .textFieldStyle(.plain)
                .autocorrectionDisabled(true)
                .focused($isSearchFocused)
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.12), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - 筛选 chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ConsoleStatusFilter.allCases, id: \.self) { filter in
                    chip(
                        text: filter.label,
                        isSelected: selectedStatus == filter,
                        accent: filter.accent
                    ) {
                        selectedStatus = filter
                    }
                }

                Rectangle()
                    .fill(.secondary.opacity(0.25))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 4)

                chip(
                    text: "全部",
                    isSelected: selectedTag == nil,
                    accent: .secondary
                ) {
                    selectedTag = nil
                }
                ForEach(availableTags, id: \.self) { tag in
                    chip(
                        text: tag,
                        isSelected: selectedTag == tag,
                        accent: ConsoleColorPalette.color(forTag: tag)
                    ) {
                        selectedTag = (selectedTag == tag) ? nil : tag
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    private func chip(
        text: String,
        isSelected: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(.caption, design: .rounded))
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isSelected
                            ? accent.opacity(0.9)
                            : Color.secondary.opacity(0.12)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 空态 / 列表

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("暂无插件调用记录")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Text("插件运行时日志将在此显示")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("没有匹配的记录")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Button("清除筛选") {
                searchText = ""
                selectedStatus = .all
                selectedTag = nil
            }
            .font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var entryList: some View {
        List {
            ForEach(filteredEntries) { entry in
                row(for: entry)
            }
        }
        .listStyle(.plain)
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
    }

    @ViewBuilder
    private func row(for entry: PluginConsoleEntry) -> some View {
        let base = ConsoleEntryRow(entry: entry)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        #if os(tvOS)
        // tvOS 的 List 不提供 listRowSeparatorTint,直接挂 base 即可。
        base
        #else
        base.listRowSeparatorTint(.secondary.opacity(0.15))
        #endif
    }
}

// MARK: - 状态筛选

/// 控制台状态筛选选项。
enum ConsoleStatusFilter: CaseIterable, Hashable {
    case all, loading, success, error

    var label: String {
        switch self {
        case .all:     return "全部"
        case .loading: return "进行中"
        case .success: return "成功"
        case .error:   return "失败"
        }
    }

    var accent: Color {
        switch self {
        case .all:     return .secondary
        case .loading: return .orange
        case .success: return .green
        case .error:   return .red
        }
    }
}

// MARK: - 颜色调色板

/// tag → 颜色。宿主功能域固定配色,其它(插件 ID)一律灰。
enum ConsoleColorPalette {
    static func color(forTag tag: String) -> Color {
        switch tag {
        case "Favorite":      return .pink
        case "FavoriteSync":  return .purple
        case "Danmaku":       return .teal
        case "Player":        return .indigo
        case "Plugin":        return .blue
        case "Credential":    return .yellow
        default:              return .gray
        }
    }
}

// MARK: - 共享时间格式

let consoleTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()

// MARK: - 跨端 View helper

extension View {
    /// tvOS 没有 textSelection,直接 no-op。
    @ViewBuilder
    func consoleSelectableText() -> some View {
        #if !os(tvOS)
        self.textSelection(.enabled)
        #else
        self
        #endif
    }
}

/// tvOS 没有 DisclosureGroup,这里退化成"标题 + 内容"的常驻折叠态。
struct ConsoleDisclosure<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
        #else
        DisclosureGroup(title, content: content)
            .font(.system(.caption, design: .rounded))
        #endif
    }
}

// MARK: - 跨端剪贴板

enum ConsolePasteboard {
    static func copy(_ string: String) {
        #if canImport(UIKit) && !os(tvOS)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
        // tvOS: 无系统剪贴板,静默丢弃
    }

    static var isAvailable: Bool {
        #if canImport(UIKit) && !os(tvOS)
        return true
        #elseif canImport(AppKit)
        return true
        #else
        return false
        #endif
    }
}
