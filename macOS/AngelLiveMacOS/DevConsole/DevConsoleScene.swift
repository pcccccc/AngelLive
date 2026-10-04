//
//  DevConsoleScene.swift
//  AngelLiveMacOS
//
//  独立窗口承载跨端的 PluginConsoleView。仅 DEBUG 构建启用,
//  通过 Debug 菜单 + ⌘⇧D 快捷键召出。
//

#if DEBUG

import SwiftUI
import AngelLiveCore

/// 独立 NSWindow Scene。`Window(_:id:)` 保证全局唯一,反复触发只激活同一个窗口。
struct DevConsoleScene: Scene {
    static let windowId = "dev-console"
    let pluginAvailability: PluginAvailabilityService

    var body: some Scene {
        Window("插件控制台", id: Self.windowId) {
            DevConsoleContent(pluginAvailability: pluginAvailability)
                .frame(minWidth: 540, minHeight: 360)
        }
        .defaultSize(width: 760, height: 560)
        .commandsRemoved()
    }
}

private struct DevConsoleContent: View {
    let pluginAvailability: PluginAvailabilityService

    var body: some View {
        Group {
            if pluginAvailability.hasAvailablePlugins {
                DeveloperConsoleView()
            } else {
                PluginConsoleView()
            }
        }
    }
}

/// 装到主 WindowGroup 上的命令集,在 macOS 的菜单栏插入"Debug"菜单,
/// 包含召出控制台的项 + ⌘⇧D 快捷键。
struct DevConsoleCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Debug") {
            Button("插件控制台") {
                openWindow(id: DevConsoleScene.windowId)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}

#endif
