 //
//  SearchRoomView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/30.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies
import SharedAssets

struct TVPlatformSearchView: View {
    let platform: Platformdescription
    @Environment(\.dismiss) private var dismiss
    @State private var liveViewModel: LiveViewModel

    init(platform: Platformdescription, appViewModel: AppState) {
        self.platform = platform
        _liveViewModel = State(initialValue: LiveViewModel(
            roomListType: .search,
            liveType: platform.liveType,
            appViewModel: appViewModel
        ))
    }

    var body: some View {
        SearchRoomView(platform: platform)
            .environment(liveViewModel)
            .environment(liveViewModel.appViewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Color.shared("sl-background")
                    .overlay {
                        if !liveViewModel.appViewModel.generalSettingsViewModel.generalDisableMaterialBackground {
                            Rectangle().fill(.thinMaterial)
                        }
                    }
                    .ignoresSafeArea()
            }
            .interactiveDismissDisabled()
            .onExitCommand { dismiss() }
            .onKeyPress(.escape, phases: .all) { press in
                if press.phase == .up {
                    dismiss()
                }
                return .handled
            }
    }
}

struct SearchRoomView: View {

    private let platform: Platformdescription?
    @State private var platformSearchText = ""
    @State private var platformSearchKind: RoomSearchKind
    @State private var authenticationRecovery: AuthenticationRecoveryRequest?
    @Environment(LiveViewModel.self) var liveViewModel
    @Environment(AppState.self) var appViewModel

    init(platform: Platformdescription? = nil) {
        self.platform = platform
        let options = platform.map { RoomSearchKind.platformOptions(for: $0.liveType) } ?? []
        _platformSearchKind = State(initialValue: options.contains(.keyword) ? .keyword : .share)
    }

    private var platformSearchOptions: [RoomSearchKind] {
        platform.map { RoomSearchKind.platformOptions(for: $0.liveType) } ?? []
    }

    private var platformSearchPrompt: String {
        platformSearchKind == .keyword ? "主播名或直播间关键词" : "平台链接/分享口令"
    }

    private var platformSearchSelection: Binding<RoomSearchKind> {
        Binding(
            get: { platformSearchKind },
            set: { kind in
                guard kind != platformSearchKind else { return }
                platformSearchText = ""
                liveViewModel.searchRequest.clear()
                platformSearchKind = kind
            }
        )
    }

    private var searchText: String {
        platform == nil ? appViewModel.searchViewModel.searchText : platformSearchText
    }

    var body: some View {

        @Bindable var appModel = appViewModel
        @Bindable var liveModel = liveViewModel

        VStack(spacing: 0) {
            // 顶部：搜索输入 + 二维码，左右分列
            HStack(alignment: .center, spacing: 40) {
                // 左侧：搜索输入区域
                VStack(alignment: .leading, spacing: 20) {
                    if let platform {
                        Text("搜索\(platform.title)")
                        if platformSearchOptions.count > 1 {
                            Picker(selection: platformSearchSelection) {
                                ForEach(platformSearchOptions, id: \.self) { kind in
                                    Text(liveViewModel.searchTypeArray[kind == .share ? 0 : 1])
                                        .tag(kind)
                                }
                            } label: {
                                Text("搜索类型")
                            }
                        }
                        HStack {
                            TextField(platformSearchPrompt, text: $platformSearchText)
                                .onSubmit(submitSearch)
                            Button("搜索", action: submitSearch)
                                .disabled(platformSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    } else {
                        Text("请输入要搜索的主播名或平台链接/分享口令/房间号")
                        Picker(selection: $appModel.searchViewModel.searchTypeIndex) {
                            ForEach(liveViewModel.searchTypeArray.indices, id: \.self) { index in
                                let text = liveViewModel.searchTypeArray[index]
                                Text(text)
                            }
                        } label: {
                            Text("搜索类型")
                        }
                        TextField("搜索", text: $appModel.searchViewModel.searchText)
                            .onSubmit(submitSearch)
                    }
                }
                .frame(maxWidth: 1200, alignment: .leading)

                Spacer()

                // 右侧：扫码输入面板
                if platform == nil {
                    searchQRPanel
                }
            }

            Spacer()

            // 搜索结果区域（占满全宽）
            if let error = liveViewModel.searchRequest.error {
                ErrorView(
                    title: error.isAuthRequired ? "搜索需要登录" : "搜索失败",
                    message: error.liveParseMessage,
                    detailMessage: error.liveParseDetail,
                    curlCommand: error.liveParseCurl,
                    showRetry: true,
                    showLoginButton: error.showsLoginAction,
                    onDismiss: {
                        liveViewModel.searchRequest.dismissError()
                    },
                    onRetry: {
                        submitSearch()
                    },
                    onLogin: {
                        authenticationRecovery = AuthenticationRecoveryRequest(pluginIDs: error.authRequiredPluginIDs)
                    }
                )
            } else if platform != nil,
                      liveViewModel.searchRequest.hasSearched,
                      !liveViewModel.searchRequest.isLoading,
                      liveViewModel.roomList.isEmpty {
                ContentUnavailableView.search(text: platformSearchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if !liveViewModel.searchRequest.authenticationRequiredPluginIDs.isEmpty {
                    Button("部分平台需要登录") {
                        authenticationRecovery = AuthenticationRecoveryRequest(
                            pluginIDs: liveViewModel.searchRequest.authenticationRequiredPluginIDs
                        )
                    }
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(370), spacing: 50), GridItem(.fixed(370), spacing: 50), GridItem(.fixed(370), spacing: 50), GridItem(.fixed(370), spacing: 50)], alignment: .center, spacing: 50) {
                        ForEach(Array(liveViewModel.roomList.enumerated()), id: \.element.id) { index, room in
                            LiveCardView(index: index, currentLiveModel: room)
                                .environment(liveViewModel)
                                .frame(width: 370, height: 280)
                        }
                        if liveViewModel.searchRequest.isLoading {
                            LoadingView()
                                .frame(width: 370, height: 280)
                                .cornerRadius(5)
                                .shimmering(active: true)
                                .redacted(reason: .placeholder)
                        }
                    }
                    .safeAreaPadding(.top, 50)
                }
            }
        }
        .fullScreenCover(item: $authenticationRecovery) { request in
            AccountManagementView(recoveryPluginIDs: request.pluginIDs)
                .frame(maxWidth: 1000)
                .padding(80)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
        }
        .simpleToast(isPresented: $liveModel.showToast, options: liveModel.toastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: liveModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(liveModel.toastTitle)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(Color.white)
            .cornerRadius(10)
        }
        .onPlayPauseCommand(perform: {
            submitSearch()
        })
        .onChange(of: appModel.searchViewModel.searchTypeIndex) { _, _ in
            guard platform == nil else { return }
            liveViewModel.searchRequest.clear()
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                liveViewModel.searchRequest.clear()
            }
        }
        .onDisappear { liveViewModel.searchRequest.cancel() }
        .onChange(of: appViewModel.remoteInputService.lastEvent?.id) {
            guard platform == nil,
                  let event = appViewModel.remoteInputService.lastEvent,
                  event.field == .search else { return }
            appModel.searchViewModel.searchText = event.value
        }
    }

    private func submitSearch() {
        if let platform {
            guard platformSearchOptions.contains(platformSearchKind) else {
                liveViewModel.searchRequest.clear()
                return
            }
            liveViewModel.submitSearch(input: platformSearchText, kind: platformSearchKind, pluginID: platform.pluginId)
            return
        }
        liveViewModel.submitSearch(
            input: appViewModel.searchViewModel.searchText,
            kind: appViewModel.searchViewModel.searchTypeIndex == 1 ? .keyword : .share
        )
    }

    // MARK: - 搜索页远程输入二维码面板

    private var searchQRPanel: some View {
        let service = appViewModel.remoteInputService
        let url = "http://\(service.localIPAddress):\(service.port)/search"
        return VStack(spacing: 16) {
            if service.isRunning && !service.localIPAddress.isEmpty {
                Image(uiImage: Common.generateQRCode(from: url))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 14)
                Text("扫码用手机输入")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(url)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                Text("正在启动远程输入...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 320)
    }
}
