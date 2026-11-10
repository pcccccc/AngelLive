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
        // 播放列表增删改(含 iCloud 同步带来的变更)后重建平台网格。
        .onReceive(NotificationCenter.default.publisher(for: .playlistInstancesDidChange)) { _ in
            Task { @MainActor in platformViewModel.refreshPlatforms(installedPluginIds: appViewModel.pluginAvailability.installedPluginIds) }
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
                            if PlaylistPlatformIdentity.isPlaylist(platform.liveType) {
                                // 播放列表平台没有插件字标图：显示用户图标（或首字）与名称。
                                // 焦点态由下方描述浮层接管；文字内容模糊后会与描述重叠，故直接淡出。
                                TVPlaylistPlatformCardContent(platform: platform)
                                    .frame(width: 370, height: 222)
                                    .opacity(focusIndex == index ? 0 : 1)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                            } else if let bigImage = TVPlatformIconProvider.bigCardImage(
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
                                .frame(width: 370, height: 222)
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
                                // 无小图的平台(如播放列表)也铺满卡片，与其他平台焦点态一致。
                                .frame(width: 370, height: 222)
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
                    .id("\(liveType.rawValue)-\(PlatformAPITokenService.shared.contentRevision)")
            } else {
                ListMainView(liveType: liveType, appViewModel: appViewModel)
                    .id("\(liveType.rawValue)-\(PlatformAPITokenService.shared.contentRevision)")
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

struct TVPlaylistPlatformCardContent: View {
    let platform: Platformdescription

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image = TVPlatformIconProvider.playlistIcon(for: platform.liveType) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Text(PlaylistIconCache.monogram(for: platform.title))
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.quaternary)
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)

            Text(platform.title)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 20)
        }
    }
}
