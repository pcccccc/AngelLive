import SwiftUI
#if !os(tvOS)
import UniformTypeIdentifiers
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, *)
public struct PlaybackTimelineView: View {
    @Bindable private var log: PlaybackEventLog
    private let onClose: (() -> Void)?
    @State private var selectedSessionID: UUID?
    @State private var selectedEntry: PlaybackEventEntry?
    @State private var exportError: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if !os(tvOS)
    @State private var exportDocument: PlaybackTimelineDocument?
    @State private var isExporting = false
    #endif

    public init(log: PlaybackEventLog = .shared, onClose: (() -> Void)? = nil) {
        self.log = log
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            #if os(iOS)
            List {
                controls
                    .buttonStyle(.borderless)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16))

                if log.entries.isEmpty {
                    ContentUnavailableView(
                        "暂无播放事件",
                        systemImage: "waveform.path.ecg",
                        description: Text("启用开发者模式后播放直播即可记录")
                    )
                } else if visibleEntries.isEmpty {
                    ContentUnavailableView("此会话暂无事件", systemImage: "timeline.selection")
                } else {
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibilityOverview
                    } else {
                        TimelineChart(entries: visibleEntries)
                            .frame(height: 160)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    ForEach(visibleEntries) { entry in
                        Button { selectedEntry = entry } label: {
                            PlaybackEventRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: rowHeight)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            #else
            VStack(spacing: 0) {
                controls
                if log.entries.isEmpty {
                    ContentUnavailableView(
                        "暂无播放事件",
                        systemImage: "waveform.path.ecg",
                        description: Text("启用开发者模式后播放直播即可记录")
                    )
                } else if visibleEntries.isEmpty {
                    ContentUnavailableView("此会话暂无事件", systemImage: "timeline.selection")
                } else {
                    TimelineChart(entries: visibleEntries)
                        .frame(height: chartHeight)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                    List(visibleEntries) { entry in
                        Button { selectedEntry = entry } label: {
                            PlaybackEventRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .frame(minHeight: rowHeight)
                    }
                    .listStyle(.plain)
                }
            }
            #endif
        }
        .sheet(item: $selectedEntry) { entry in
            PlaybackEventDetailView(entry: entry)
        }
        .alert("无法导出播放时间轴", isPresented: exportErrorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportError ?? "未知错误")
        }
        #if !os(tvOS)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "AngelLive-Playback-Timeline"
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
            exportDocument = nil
        }
        #endif
        #if os(tvOS)
        .onExitCommand {
            if selectedEntry != nil {
                selectedEntry = nil
            } else {
                onClose?()
            }
        }
        #endif
    }

    private var controls: some View {
        Group {
            #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    sessionPicker
                    actions
                }
            } else {
                adaptiveControls
            }
            #else
            adaptiveControls
            #endif
        }
        #if !os(iOS)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        #endif
    }

    private var adaptiveControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { sessionPicker; Spacer(); actions }
            VStack(alignment: .leading, spacing: 8) { sessionPicker; actions }
        }
    }

    private var sessionPicker: some View {
        Group {
            if sessions.isEmpty {
                Text("暂无会话")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("播放会话，暂无会话")
            } else {
                Picker("播放会话", selection: sessionBinding) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        Text("播放会话 \(index + 1)/\(sessions.count) · \(session.date.formatted(date: .omitted, time: .standard))")
                            .tag(session.id)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("播放会话")
            }
        }
        .frame(maxWidth: sessionPickerMaximumWidth, alignment: .leading)
    }

    private var actions: some View {
        Group {
            #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    clearButton.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    exportButton.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) { clearButton; exportButton }
            }
            #else
            HStack(spacing: 10) {
                clearButton
                #if !os(tvOS)
                exportButton
                #endif
            }
            #endif
        }
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            log.clear()
            selectedSessionID = nil
        } label: {
            Label("清空", systemImage: "trash")
        }
    }

    #if !os(tvOS)
    private var exportButton: some View {
        Button(action: export) { Label("导出", systemImage: "square.and.arrow.up") }
    }
    #endif

    private var sessionPickerMaximumWidth: CGFloat? {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize ? .infinity : 360
        #else
        360
        #endif
    }

    #if os(iOS)
    private var accessibilityOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("事件概览")
                .font(.headline)
            Text(accessibilityOverviewText)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    private var accessibilityOverviewText: String {
        guard let first = visibleEntries.first?.elapsed, let last = visibleEntries.last?.elapsed else {
            return "共 0 条事件"
        }
        return "共 \(visibleEntries.count) 条事件，记录范围 \(String(format: "%.2f", first))–\(String(format: "%.2f", last)) 秒，下方为完整事件列表"
    }
    #endif

    private var sessions: [(id: UUID, date: Date)] {
        Dictionary(grouping: log.entries, by: \.sessionID)
            .compactMap { id, entries in entries.map(\.date).min().map { (id, $0) } }
            .sorted { $0.date < $1.date }
    }

    private var sessionBinding: Binding<UUID> {
        Binding(
            get: { selectedSessionID.flatMap { selected in sessions.contains { $0.id == selected } ? selected : nil }
                ?? sessions.last?.id
                ?? UUID() },
            set: { selectedSessionID = $0 }
        )
    }

    private var visibleEntries: [PlaybackEventEntry] {
        guard let id = sessions.contains(where: { $0.id == selectedSessionID }) ? selectedSessionID : sessions.last?.id else {
            return []
        }
        return log.entries.filter { $0.sessionID == id }.sorted { $0.elapsed < $1.elapsed }
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    private var chartHeight: CGFloat {
        #if os(tvOS)
        260
        #elseif os(macOS)
        180
        #else
        160
        #endif
    }

    private var rowHeight: CGFloat {
        #if os(tvOS)
        76
        #elseif os(macOS)
        32
        #else
        44
        #endif
    }

    #if !os(tvOS)
    private func export() {
        do {
            exportDocument = PlaybackTimelineDocument(data: try log.exportJSON())
            isExporting = true
        } catch {
            exportError = error.localizedDescription
        }
    }
    #endif

}

private struct PlaybackEventRow: View {
    let entry: PlaybackEventEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { elapsed; content }
            } else {
                adaptiveRow
            }
            #else
            adaptiveRow
            #endif
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var adaptiveRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) { elapsed; content }
            VStack(alignment: .leading, spacing: 5) { elapsed; content }
        }
    }

    private var elapsed: some View {
        Text(String(format: "%7.2fs", entry.elapsed))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: elapsedWidth, alignment: .leading)
    }

    private var elapsedWidth: CGFloat? {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize ? nil : 72
        #else
        72
        #endif
    }

    private var content: some View {
        HStack(spacing: 10) {
            if showsDecorativeIcon {
                Image(systemName: entry.event.timelineIcon)
                    .foregroundStyle(entry.event.isFailure ? .red : .secondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.event.timelineTitle)
                    .foregroundStyle(entry.event.isFailure ? .red : .primary)
                    .fixedSize(horizontal: false, vertical: expandsTextVertically)
                if let summary = entry.event.timelineSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(summaryLineLimit)
                        .fixedSize(horizontal: false, vertical: expandsTextVertically)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var showsDecorativeIcon: Bool {
        #if os(iOS)
        !dynamicTypeSize.isAccessibilitySize
        #else
        true
        #endif
    }

    private var expandsTextVertically: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    private var summaryLineLimit: Int? {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize ? nil : 2
        #else
        2
        #endif
    }

    private var accessibilityText: String {
        [String(format: "%.2f 秒", entry.elapsed), entry.event.timelineTitle, entry.event.timelineSummary]
            .compactMap { $0 }
            .joined(separator: "，")
    }
}

private struct TimelineChart: View {
    let entries: [PlaybackEventEntry]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Canvas { context, size in
            let maximum = max(entries.map(\.elapsed).max() ?? 1, 1)
            let labelWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 132 : 92
            let bottomHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 58 : 38
            let plotWidth = max(size.width - labelWidth - 12, 1)
            let plotHeight = max(size.height - bottomHeight, 1)
            let laneHeight = plotHeight / 5
            let laneNames = ["连接", "状态", "恢复", "失败"]
            for lane in 0..<4 {
                let y = laneHeight * (CGFloat(lane) + 0.5)
                context.draw(
                    Text(laneNames[lane]).font(.caption).foregroundStyle(.secondary),
                    at: CGPoint(x: 0, y: y),
                    anchor: .leading
                )
                var line = Path()
                line.move(to: CGPoint(x: labelWidth, y: y))
                line.addLine(to: CGPoint(x: labelWidth + plotWidth, y: y))
                context.stroke(line, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
            }
            for entry in entries where !entry.event.isSample {
                let x = labelWidth + plotWidth * CGFloat(entry.elapsed / maximum)
                let y = laneHeight * (CGFloat(entry.event.timelineLane) + 0.5)
                let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(entry.event.isFailure ? .red : .accentColor))
            }

            let samples = entries.compactMap { entry -> (TimeInterval, Double)? in
                guard case .sample(_, let playhead, _) = entry.event else { return nil }
                return (entry.elapsed, playhead)
            }
            if samples.count > 1 {
                let maximumPlayhead = max(samples.map(\.1).max() ?? 1, 1)
                var path = Path()
                for (index, sample) in samples.enumerated() {
                    let point = CGPoint(
                        x: labelWidth + plotWidth * CGFloat(sample.0 / maximum),
                        y: laneHeight * 4 + laneHeight * CGFloat(1 - sample.1 / maximumPlayhead)
                    )
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(.cyan), lineWidth: 2)
            }
            context.draw(
                Text("播放进度（秒）").font(.caption).foregroundStyle(.cyan),
                at: CGPoint(x: 0, y: laneHeight * 4.5),
                anchor: .leading
            )
            let axisY = plotHeight + 8
            context.draw(Text("0 秒").font(.caption2).foregroundStyle(.secondary),
                         at: CGPoint(x: labelWidth, y: axisY), anchor: .topLeading)
            context.draw(Text("\(String(format: "%.1f", maximum)) 秒").font(.caption2).foregroundStyle(.secondary),
                         at: CGPoint(x: labelWidth + plotWidth, y: axisY), anchor: .topTrailing)
        }
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("播放事件时间轴，共 \(entries.count) 条事件")
    }
}

private struct PlaybackEventDetailView: View {
    let entry: PlaybackEventEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            List {
                Section("基本信息") {
                    row("会话", entry.sessionID.uuidString)
                    row("时间", String(format: "%.3f 秒", entry.elapsed))
                    row("记录时间", entry.date.formatted(date: .abbreviated, time: .standard))
                    row("事件", entry.event.timelineTitle)
                }
                if let summary = entry.event.timelineSummary {
                    Section("详情") { Text(summary) }
                }
            }
            .navigationTitle("播放事件")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("关闭") { dismiss() } } }
            #if os(tvOS)
            .onExitCommand { dismiss() }
            #endif
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        Group {
            #if os(iOS)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(value)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                detailRow(title, value)
            }
            #else
            detailRow(title, value)
            #endif
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

private extension PlaybackEvent {
    var timelineTitle: String {
        switch self {
        case .sessionStarted: "会话开始"
        case .sourceAssigned: "已选择播放源"
        case .engineStateChanged: "播放状态变化"
        case .sample: "播放采样"
        case .recovery: "恢复操作"
        case .startupCompleted: "起播完成"
        case .startupFailed: "起播失败"
        case .preferenceApplied: "应用线路偏好"
        case .recoveryExhausted: "恢复次数已用尽"
        case .sessionEnded: "会话结束"
        }
    }

    var timelineSummary: String? {
        switch self {
        case .sessionStarted, .recoveryExhausted, .sessionEnded: nil
        case .sourceAssigned(let line, let quality): "线路 \(line)，清晰度 \(quality)"
        case .engineStateChanged(let state, let isPlaying): "\(state.rawValue)，\(isPlaying ? "正在播放" : "未播放")"
        case .sample(let bytesRead, let playhead, let buffered):
            "读取 \(bytesRead) 字节，进度 \(String(format: "%.2f", playhead)) 秒，缓冲 \(String(format: "%.2f", buffered)) 秒"
        case .recovery(let action, let attempt, let limit): "\(action.description) · \(attempt)/\(limit)"
        case .startupCompleted(let milliseconds): "\(String(format: "%.0f", milliseconds)) 毫秒"
        case .startupFailed(let code): code.rawValue
        case .preferenceApplied(let originalIndex, let chosenIndex): "线路 \(originalIndex) → \(chosenIndex)"
        }
    }

    var timelineIcon: String {
        switch self {
        case .sessionStarted, .sessionEnded: "play.circle"
        case .sourceAssigned, .preferenceApplied: "point.3.connected.trianglepath.dotted"
        case .engineStateChanged: "waveform"
        case .sample: "chart.xyaxis.line"
        case .recovery: "arrow.trianglehead.2.counterclockwise"
        case .startupCompleted: "checkmark.circle"
        case .startupFailed, .recoveryExhausted: "exclamationmark.triangle"
        }
    }

    var timelineLane: Int {
        switch self {
        case .sessionStarted, .sourceAssigned, .startupCompleted, .preferenceApplied, .sessionEnded: 0
        case .engineStateChanged: 1
        case .recovery: 2
        case .startupFailed, .recoveryExhausted: 3
        case .sample: 4
        }
    }

    var isFailure: Bool {
        switch self { case .startupFailed, .recoveryExhausted: true; default: false }
    }

    var isSample: Bool { if case .sample = self { true } else { false } }
}

#if !os(tvOS)
private struct PlaybackTimelineDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif
