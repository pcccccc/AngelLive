//
//  PlatformView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/11.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

extension LiveType: @retroactive Identifiable {
    public var id: String { rawValue }
}

struct PlatformView: View {
    let column = Array(repeating: GridItem(.fixed(380), spacing: 50), count: 4)
    @State private var platformViewModel = PlatformViewModel()
    @FocusState private var focusIndex: Int?
    @Environment(AppState.self) private var appViewModel
    @State private var selectedLiveType: LiveType?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // cover 由 ContentView 根部统一持有,所有 tab 共享 — 这里不再本地持有。
        Group {
            if appViewModel.pluginAvailability.hasAvailablePlugins {
                platformGridView
            } else {
                TVShellConfigView()
                    .environment(appViewModel)
            }
        }
        .task {
            await appViewModel.pluginAvailability.checkAvailability()
            platformViewModel.refreshPlatforms(installedPluginIds: appViewModel.pluginAvailability.installedPluginIds)
        }
        .onChange(of: appViewModel.pluginAvailability.installedPluginIds) { _, installedPluginIds in
            platformViewModel.refreshPlatforms(installedPluginIds: installedPluginIds)
            if installedPluginIds.isEmpty {
                selectedLiveType = nil
            }
        }
    }

    private var platformGridView: some View {
        ScrollView {
            LazyVGrid(columns: column, alignment: .center, spacing: 50) {
                // 按元素迭代 + pluginId 作为稳定 id；避免 ForEach(_.indices, id: \.self)
                // 在数组 mutate 时缓存的 index 落到新数组之外触发 "Index out of range"。
                ForEach(Array(platformViewModel.platformInfo.enumerated()), id: \.element.id) { index, platform in
                    Button {
                        selectedLiveType = platform.liveType
                    } label: {
                        ZStack {
                            Image("platform-bg")
                                .resizable()
                                .frame(width: 370, height: 222)
                            if let bigImage = TVPlatformIconProvider.bigCardImage(
                                for: platform,
                                isDarkMode: colorScheme == .dark
                            ) {
                                Image(uiImage: bigImage)
                                    .resizable()
                                    .frame(width: 370, height: 222)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                    .blur(radius: focusIndex == index ? 10 : 0)
                            }

                            if appViewModel.generalSettingsViewModel.generalDisableMaterialBackground {
                                ZStack {
                                    if let smallImage = TVPlatformIconProvider.smallCardImage(
                                        for: platform,
                                        isDarkMode: colorScheme == .dark
                                    ) {
                                        Image(uiImage: smallImage)
                                            .resizable()
                                            .frame(width: 370, height: 222)
                                    }
                                    Text(platform.descripiton)
                                        .font(.body)
                                        .multilineTextAlignment(.leading)
                                        .padding([.leading, .trailing], 15)
                                        .padding(.top, 50)

                                }
                                .background(Color("sl-background", bundle: nil))
                                .opacity(focusIndex == index ? 1 : 0)
                                .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                            } else {
                                ZStack {
                                    if let smallImage = TVPlatformIconProvider.smallCardImage(
                                        for: platform,
                                        isDarkMode: colorScheme == .dark
                                    ) {
                                        Image(uiImage: smallImage)
                                            .resizable()
                                            .frame(width: 370, height: 222)
                                    }
                                    Text(platform.descripiton)
                                        .font(.body)
                                        .multilineTextAlignment(.leading)
                                        .padding([.leading, .trailing], 15)
                                        .padding(.top, 50)

                                }
                                .background(.thinMaterial)
                                .opacity(focusIndex == index ? 1 : 0)
                                .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                            }

                        }
                    }
                    .buttonStyle(.card)
                    .background(.clear)
                    .focused($focusIndex, equals: index)
                    .transition(.moveAndOpacity)
                    .animation(.easeInOut(duration: 0.25), value: true)
                    .frame(width: 380, height: 230)
                }

            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
        }
        .fullScreenCover(item: $selectedLiveType) { liveType in
            if appViewModel.generalSettingsViewModel.generalDisableMaterialBackground {
                ListMainView(liveType: liveType, appViewModel: appViewModel)
                    .background(
                        Color("sl-background", bundle: nil)
                    )
                    .safeAreaPadding(.all)
                    .id(liveType)
            } else {
                ListMainView(liveType: liveType, appViewModel: appViewModel)
                    .id(liveType)
            }
        }
    }
}

extension AnyTransition {
    static var moveAndOpacity: AnyTransition {
        AnyTransition.opacity
    }
}

#Preview {
    PlatformView()
}
