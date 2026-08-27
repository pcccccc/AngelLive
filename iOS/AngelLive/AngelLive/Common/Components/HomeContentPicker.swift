//
//  HomeContentPicker.swift
//  AngelLive
//
//  推荐页与收藏页共用的首页内容/平台胶囊。
//

import AngelLiveCore
import SwiftUI
import UIKit

struct HomeContentPicker: View {
    let options: [HomePlatformOption]
    /// 推荐页滚动时让胶囊与导航栏材质交叉淡化；收藏页工具栏固定为 1。
    let glassOpacity: CGFloat
    var onSelectPlatform: ((String?) -> Void)?
    var onNavigateToRecommendations: (() -> Void)?

    @AppStorage(HomePagePreference.storageKey, store: .shared)
    private var homePagePreference = HomePagePreference.recommendations
    @AppStorage(HomePagePreference.selectedPluginStorageKey, store: .shared)
    private var selectedPluginId = ""

    private var selectedOption: HomePlatformOption? {
        guard homePagePreference == .recommendations,
              !selectedPluginId.isEmpty else {
            return nil
        }
        return options.first { $0.pluginId == selectedPluginId }
    }

    private var selectedName: String {
        if homePagePreference == .favorites {
            return HomePagePreference.favorites.displayName
        }
        return selectedOption?.displayName ?? HomePagePreference.recommendations.displayName
    }

    var body: some View {
        Menu {
            // 首页内容固定放在第一组，平台筛选统一放在下方分区。
            Section {
                Button(action: selectRecommendations) {
                    Label {
                        Text(HomePagePreference.recommendations.displayName)
                    } icon: {
                        recommendationIcon(size: 18)
                    }
                }
                .accessibilityLabel(HomePagePreference.recommendations.displayName)

                Button(action: selectFavorites) {
                    Label(HomePagePreference.favorites.displayName, systemImage: "heart.fill")
                }
                .accessibilityLabel(HomePagePreference.favorites.displayName)
            }

            if !options.isEmpty {
                Section {
                    ForEach(options) { option in
                        Button {
                            selectPlatform(option)
                        } label: {
                            Label {
                                Text(option.displayName)
                            } icon: {
                                HomePlatformIcon(option: option, size: 18)
                            }
                        }
                        .accessibilityLabel(option.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                selectedIcon

                Text(selectedName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(AppConstants.Colors.primaryText)
            }
            .padding(.leading, 7)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .homeContentPickerLabelBackground(opacity: glassOpacity)
        }
        // Keep this utility control neutral over changing artwork.
        .tint(AppConstants.Colors.primaryText)
        .menuOrder(.fixed)
        .accessibilityLabel("首页内容与直播平台，当前为\(selectedName)")
        .accessibilityHint("选择推荐、收藏或支持首页的平台")
    }

    @ViewBuilder
    private var selectedIcon: some View {
        if homePagePreference == .favorites {
            Image(systemName: "heart.fill")
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        } else if let selectedOption {
            HomePlatformIcon(option: selectedOption, size: 24)
        } else {
            recommendationIcon(size: 22)
        }
    }

    @ViewBuilder
    private func recommendationIcon(size: CGFloat) -> some View {
        Image(systemName: "sparkles")
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func selectRecommendations() {
        selectedPluginId = ""
        onSelectPlatform?(nil)
        homePagePreference = .recommendations
        onNavigateToRecommendations?()
    }

    private func selectFavorites() {
        homePagePreference = .favorites
    }

    private func selectPlatform(_ option: HomePlatformOption) {
        selectedPluginId = option.pluginId
        onSelectPlatform?(option.pluginId)
        homePagePreference = .recommendations
        onNavigateToRecommendations?()
    }
}

private struct HomePlatformIcon: View {
    let option: HomePlatformOption
    let size: CGFloat

    var body: some View {
        Group {
            if let image = PlatformIconProvider.tabImage(for: option.liveType) {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Circle()
                    .fill(.secondary.opacity(0.16))
                    .overlay {
                        Text(String(option.displayName.prefix(1)))
                            .font(.system(size: size * 0.46, weight: .bold))
                            .foregroundStyle(.primary)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct HomeContentPickerToolbarModifier: ViewModifier {
    @Environment(PlatformViewModel.self) private var platformViewModel
    @Environment(\.dismiss) private var dismiss

    private var pickerGlassOpacity: CGFloat {
        if #available(iOS 26.0, *) {
            // Liquid Glass toolbars already give controls their own capsule.
            0
        } else {
            // Earlier systems need the app's material capsule fallback.
            1
        }
    }

    private var options: [HomePlatformOption] {
        platformViewModel.platformInfo.compactMap { platform in
            guard PlatformCapability.supports(.homeFeed, for: platform.liveType) else {
                return nil
            }
            return HomePlatformOption(
                pluginId: platform.pluginId,
                displayName: platform.title,
                liveType: platform.liveType
            )
        }
    }

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HomeContentPicker(
                    options: options,
                    glassOpacity: pickerGlassOpacity,
                    onSelectPlatform: nil,
                    onNavigateToRecommendations: { dismiss() }
                )
            }
        }
    }
}

extension View {
    func homeContentPickerToolbar() -> some View {
        modifier(HomeContentPickerToolbarModifier())
    }

    @ViewBuilder
    func homeContentPickerLabelBackground(opacity: CGFloat) -> some View {
        if opacity <= 0 {
            self
        } else if #available(iOS 26.0, *) {
            background {
                Color.clear
                    .glassEffect(.regular, in: .capsule)
                    .opacity(opacity)
            }
        } else {
            background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .opacity(opacity)
            }
        }
    }
}
