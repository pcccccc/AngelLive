import SwiftUI
import AngelLiveCore

struct DanmakuKeywordBlocklistView: View {
    @Bindable var settings: DanmuSettingModel
    @State private var draft = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: AppConstants.Spacing.sm) {
                    TextField("输入要屏蔽的关键词", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addKeyword)

                    Button(action: addKeyword) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .tint(AppConstants.Colors.accent)
                    .disabled(!canAddKeyword)
                    .accessibilityLabel("添加屏蔽关键词")
                }
            } header: {
                Text("新增关键词")
            } footer: {
                Text("命中关键词的弹幕不会显示在聊天列表或飞屏中。")
            }

            Section("已屏蔽 \(settings.blockedKeywords.count) 个") {
                if settings.blockedKeywords.isEmpty {
                    Label("暂未添加屏蔽关键词", systemImage: "text.badge.xmark")
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                } else {
                    ForEach(settings.blockedKeywords, id: \.self) { keyword in
                        HStack {
                            Text(keyword)
                                .foregroundStyle(AppConstants.Colors.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                settings.removeBlockedKeyword(keyword)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(AppConstants.Colors.error)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel("删除关键词 \(keyword)")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("关键词屏蔽")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var normalizedDraft: String? {
        DanmuSettingModel.normalizedBlockedKeywords([draft]).first
    }

    private var canAddKeyword: Bool {
        guard let normalizedDraft else { return false }
        return !settings.blockedKeywords.contains {
            $0.compare(normalizedDraft, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
        }
    }

    private func addKeyword() {
        guard let normalizedDraft, canAddKeyword else { return }
        settings.addBlockedKeyword(normalizedDraft)
        draft = ""
    }
}
