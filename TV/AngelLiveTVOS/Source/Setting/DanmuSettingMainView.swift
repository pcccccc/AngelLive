//
//  DanmuSettingMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/8/24.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct DanmuSettingMainView: View {
    
    @Environment(AppState.self) var appViewModel
    @Environment(\.usesFullUI) private var usesFullUI
    @FocusState var showDanmuView: Bool
    @FocusState private var keywordsFocused: Bool
    @State private var showsKeywordBlocklist = false
    
    var body: some View {
        
        @Bindable var danmuModel = appViewModel.danmuSettingsViewModel
        
        VStack(spacing: 50) {
            Spacer()
            Toggle(isOn: $danmuModel.showDanmu) {
                Text("开启弹幕")
                    .foregroundColor(.primary)
            }
                .frame(height: 45)
                .focused($showDanmuView)
            Toggle(isOn: $danmuModel.showColorDanmu) {
                Text("开启彩色弹幕")
                    .foregroundColor(.primary)
            }
                .frame(height: 45)
            if usesFullUI {
                keywordButton.focused($keywordsFocused)
            } else {
                keywordButton
            }
            HStack {
                Text("字体大小：")
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize = max(10, appViewModel.danmuSettingsViewModel.danmuFontSize - 5)
                } label: {
                    Text("-5")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)
                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize = max(10, appViewModel.danmuSettingsViewModel.danmuFontSize - 1)
                } label: {
                    Text("-1")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)

                Text("\(appViewModel.danmuSettingsViewModel.danmuFontSize)")
                    .font(.system(size: CGFloat(appViewModel.danmuSettingsViewModel.danmuFontSize)))

                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize = min(100, appViewModel.danmuSettingsViewModel.danmuFontSize + 1)
                } label: {
                    Text("+1")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)

                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize = min(100, appViewModel.danmuSettingsViewModel.danmuFontSize + 5)
                } label: {
                    Text("+5")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                
                .clipShape(.circle)
                .frame(width: 40, height:40)
                Spacer()
            }
            .frame(height: 45)
            HStack {
                Text("这是一条测试弹幕")
                    .foregroundColor(.primary)
                    .font(.system(size: CGFloat(appViewModel.danmuSettingsViewModel.danmuFontSize)))
            }
            .frame(height: 45)
            HStack {
                Text("    透明度：")
                    .foregroundColor(.primary)
                TextField("透明度：(0.1-1.0)", text: $danmuModel.danmuAlphaString)
                    .keyboardType(.decimalPad)
                    .submitLabel(.done)
                    .onChange(of: appViewModel.danmuSettingsViewModel.danmuAlphaString) { oldValue, newValue in
                        if Double(newValue) != nil && Double(newValue) ?? 0 > 0.09 && Double(newValue) ?? 0 < 1.01  {
                            appViewModel.danmuSettingsViewModel.danmuAlpha = Double(newValue)!
                        }
                    }
                    .onAppear {
                        appViewModel.danmuSettingsViewModel.danmuAlphaString = "\(appViewModel.danmuSettingsViewModel.danmuAlpha)"
                    }
                
            }
            .frame(height: 45)
            HStack {
                Text("弹幕速度：")
                    .foregroundColor(.primary)
                Picker(selection: Binding(get: {
                    appViewModel.danmuSettingsViewModel.danmuSpeedIndex
                }, set: { value in
                    appViewModel.danmuSettingsViewModel.danmuSpeedIndex = value
                    switch appViewModel.danmuSettingsViewModel.danmuSpeedIndex {
                        case 0:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.5
                        case 1:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.7
                        case 2:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.85
                        default:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.7
                    }
                })) {
                    ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                        // 需要有一个变量text。不然会自动帮忙加很多0
                        let text = DanmuSettingModel.danmuSpeedArray[index]
                        Text(text)
                    }
                } label: {
                    Text("弹幕速度：")
                }
            }
            .frame(height: 45)
            HStack {
                Text("显示区域：")
                    .foregroundColor(.primary)
                Menu(content: {
                    ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                        Button(DanmuSettingModel.danmuAreaArray[index]) {
                            appViewModel.danmuSettingsViewModel.danmuAreaIndex = index
                        }
                    }
                }, label: {
                    Text("\(DanmuSettingModel.danmuAreaArray[appViewModel.danmuSettingsViewModel.danmuAreaIndex])")
                        .foregroundColor(.primary)
                        .frame(width: 535, height: 45, alignment: .center)
                })
                
            }
            .frame(height: 45)
            Spacer()
        }
        .tvFullUIModalPresentation(fullUI: usesFullUI, isPresented: $showsKeywordBlocklist, onDismiss: {
            if usesFullUI { keywordsFocused = true }
        }) {
            DanmakuKeywordBlocklistSheet(
                settings: appViewModel.danmuSettingsViewModel,
                isPresented: $showsKeywordBlocklist
            )
        }
    }

    private var keywordButton: some View {
        Button("屏蔽关键词（\(appViewModel.danmuSettingsViewModel.blockedKeywords.count)）") {
            showsKeywordBlocklist = true
        }
        .frame(height: 45)
    }
}

struct DanmakuKeywordBlocklistSheet: View {
    @Environment(\.usesFullUI) private var usesFullUI
    @Binding private var keywords: [String]
    @Binding private var isPresented: Bool
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    init(settings: DanmuSettingModel, isPresented: Binding<Bool>) {
        _keywords = Binding(get: { settings.blockedKeywords }, set: { settings.blockedKeywords = $0 })
        _isPresented = isPresented
    }

#if DEBUG
    init(auditSettings: TVUIAuditSettings, isPresented: Binding<Bool>) {
        _keywords = Binding(
            get: { auditSettings.blockedKeywords },
            set: { auditSettings.blockedKeywords = DanmuSettingModel.normalizedBlockedKeywords($0) }
        )
        _isPresented = isPresented
    }
#endif

    var body: some View {
        if usesFullUI {
            TVFullUIModalCard(title: "屏蔽关键词", subtitle: "包含这些关键词的弹幕不会显示在聊天或画面中。",
                              closeIdentifier: "tv.settings.danmaku.keywords.done", onClose: { isPresented = false }) {
                TextField(text: $draft) {
                    Text("输入要屏蔽的关键词")
                        .foregroundStyle(inputFocused ? Color.black.opacity(0.8) : .white.opacity(0.85))
                }
                .textFieldStyle(.plain)
                .font(.system(size: 26))
                .foregroundStyle(inputFocused ? Color.black : .white)
                .padding(.horizontal, 20)
                .frame(minHeight: 70)
                .background(inputFocused ? Color.white : .white.opacity(0.12), in: .rect(cornerRadius: 14))
                .focused($inputFocused)
                .focusEffectDisabled()
                .onSubmit(addKeyword)
                .accessibilityLabel("输入要屏蔽的关键词")
                .accessibilityIdentifier("tv.settings.danmaku.keywords.input")
                TVFullUIModalRow(action: addKeyword) {
                    Label("添加关键词", systemImage: "plus")
                }
                .disabled(!canAddKeyword)
                .accessibilityIdentifier("tv.settings.danmaku.keywords.add")

                Text("已屏蔽 \(keywords.count) 个")
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.top, 12)
                ForEach(keywords, id: \.self) { keyword in
                    TVFullUIModalRow(action: { keywords.removeAll { $0 == keyword } }) {
                        HStack {
                            Text(verbatim: keyword)
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                    .accessibilityLabel("删除关键词 \(keyword)")
                }
            }
        } else {
            legacySheet
        }
    }

    private var legacySheet: some View {
        NavigationStack {
            Form {
                Section("新增关键词") {
                    TextField("输入要屏蔽的关键词", text: $draft)
                        .onSubmit(addKeyword)
                        .accessibilityIdentifier("tv.settings.danmaku.keywords.input")
                    Button("添加", action: addKeyword)
                        .disabled(!canAddKeyword)
                        .accessibilityIdentifier("tv.settings.danmaku.keywords.add")
                }

                Section("已屏蔽 \(keywords.count) 个") {
                    if keywords.isEmpty {
                        Text("命中关键词的弹幕不会显示在聊天或飞屏中")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keywords, id: \.self) { keyword in
                            HStack {
                                Text(keyword)
                                Spacer()
                                Button("删除", role: .destructive) {
                                    keywords.removeAll { $0 == keyword }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("关键词屏蔽")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { isPresented = false }
                        .accessibilityIdentifier("tv.settings.danmaku.keywords.done")
                }
            }
        }

    }

    private var normalizedDraft: String? {
        DanmuSettingModel.normalizedBlockedKeywords([draft]).first
    }

    private var canAddKeyword: Bool {
        guard let normalizedDraft else { return false }
        return !keywords.contains {
            $0.compare(normalizedDraft, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
        }
    }

    private func addKeyword() {
        guard let normalizedDraft, canAddKeyword else { return }
        keywords.append(normalizedDraft)
        draft = ""
    }
}

#Preview {
    DanmuSettingMainView()
}
