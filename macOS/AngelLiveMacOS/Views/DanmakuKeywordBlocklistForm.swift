import SwiftUI
import AngelLiveCore

struct DanmakuKeywordBlocklistForm: View {
    @Bindable var settings: DanmuSettingModel
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("输入要屏蔽的关键词", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addKeyword)

                Button(action: addKeyword) {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(!canAddKeyword)
            }

            if settings.blockedKeywords.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .foregroundStyle(.tertiary)
                    Text("尚未添加关键词")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(settings.blockedKeywords.indices, id: \.self) { index in
                        let keyword = settings.blockedKeywords[index]
                        HStack(spacing: 10) {
                            Image(systemName: "nosign")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)

                            Text(keyword)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                settings.removeBlockedKeyword(keyword)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("删除关键词 \(keyword)")
                            .accessibilityLabel("删除关键词 \(keyword)")
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)

                        if index < settings.blockedKeywords.count - 1 {
                            Divider()
                                .padding(.leading, 30)
                        }
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 4)
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
