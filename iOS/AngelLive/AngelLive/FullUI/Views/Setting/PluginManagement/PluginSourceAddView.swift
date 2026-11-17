import SwiftUI
import AngelLiveCore

struct PluginSourceAddView: View {
    @Environment(PluginSourceManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var input = ""
    @State private var processing = false
    @State private var completed = false
    @FocusState private var inputFocused: Bool
    @State private var localError: String?
    @State private var playlistURL: String?
    @State private var shakeTrigger = 0
    @State private var detent: PresentationDetent = .medium
    @State private var addTask: Task<Void, Never>?
    let onAdded: ([String]) -> Void
    var body: some View {
        let shouldReduceMotion = reduceMotion
        return Group {
            if let playlistURL {
                PlaylistEditorView(mode: .add(sourceURL: playlistURL)) { dismiss() }
            } else {
                ScrollView {
                    VStack(spacing: PluginManagementLayout.detailSpacing) {
                        VStack(spacing: 8) {
                            Image(systemName: "link").font(.largeTitle).foregroundStyle(.tint)
                                .frame(width: 64, height: 64).background(PluginManagementLayout.primaryAction.opacity(0.12), in: Circle()).accessibilityHidden(true)
                            Text("添加来源").font(.title2.bold())
                            Text("插件来源地址、兑换码或 m3u 播放列表").font(.subheadline).foregroundStyle(.secondary)
                        }.multilineTextAlignment(.center)
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("https:// 或兑换码", text: $input)
                                .keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never)
                                .autocorrectionDisabled().submitLabel(.go).onSubmit(add)
                                .focused($inputFocused).disabled(processing)
                                .padding(PluginManagementLayout.contentInset).background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous).stroke(localError == nil ? Color.clear : .red, lineWidth: 1.5))
                                .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakeTrigger) { content, x in content.offset(x: shouldReduceMotion ? 0 : x) } keyframes: { _ in
                                    LinearKeyframe(-4, duration: 0.08); LinearKeyframe(4, duration: 0.08)
                                    LinearKeyframe(-3, duration: 0.08); LinearKeyframe(2, duration: 0.08); LinearKeyframe(0, duration: 0.08)
                                }
                            Text(localError ?? (completed ? "已添加来源" : processing ? "正在读取来源…" : "添加后会读取来源里的插件，不会自动安装。"))
                                .font(.footnote).foregroundStyle(localError == nil ? Color.secondary : .red)
                                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 8)
                        }
                        addButton
                    }.padding(PluginManagementLayout.contentInset).frame(maxWidth: PluginManagementLayout.readingWidth).frame(maxWidth: .infinity)
                }.background(PluginManagementLayout.pageBackground)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(processing) } }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent).presentationDragIndicator(.visible)
        .tint(PluginManagementLayout.primaryAction)
        .interactiveDismissDisabled(processing)
        .onChange(of: playlistURL) { _, url in if url != nil { detent = .large } }
        .sensoryFeedback(.warning, trigger: shakeTrigger)
        .sensoryFeedback(.success, trigger: completed) { old, new in !old && new }
        .task { inputFocused = true }
        .onDisappear { addTask?.cancel(); addTask = nil }
    }

    private var addButton: some View {
        Button(action: add) {
            Group {
                if completed {
                    Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(.green)
                } else if processing {
                    ProgressView().controlSize(.large).tint(PluginManagementLayout.primaryAction)
                } else {
                    Text("添加").font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 14)
                }
            }
            .frame(width: processing ? 50 : nil)
            .frame(maxWidth: processing ? nil : .infinity, minHeight: 50)
            .background {
                if !processing { Capsule().fill(PluginManagementLayout.primaryAction) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PluginPressButtonStyle())
        .disabled(processing || manager.isManagementBusy)
        .accessibilityLabel(completed ? "来源已添加" : processing ? "正在读取来源" : "添加来源")
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.42), value: processing)
        .animation(.easeOut(duration: 0.2), value: completed)
    }

    private func add() {
        guard !processing, !manager.isManagementBusy else { return }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { fail("请先输入来源地址或兑换码。"); return }
        guard manager.commitPendingUninstall() else {
            fail(manager.errorMessage ?? "未能完成之前的卸载，请重试。")
            return
        }
        inputFocused = false
        processing = true; completed = false; localError = nil
        addTask = Task {
            defer { processing = false }
            let result = await manager.addSourceOrDetectPlaylist(value)
            guard !Task.isCancelled else { return }
            switch result {
            case .playlist(let url): playlistURL = url
            case .sources(let urls):
                if urls.isEmpty { fail(manager.errorMessage ?? "无法识别这个来源，请检查地址或兑换码。") }
                else {
                    completed = true
                    do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                    guard !Task.isCancelled else { return }
                    onAdded(urls); dismiss()
                }
            }
        }
    }
    private func fail(_ message: String) { localError = SupportDiagnosticSanitizer.text(message); shakeTrigger += 1 }
}
