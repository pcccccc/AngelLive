import SwiftUI

struct MacPluginManagementActions {
    let canUpdate: Bool
    let canCheck: Bool
    let canAddSource: Bool
    let canShowSources: Bool
    let update: () -> Void
    let check: () -> Void
    let addSource: () -> Void
    let showSources: () -> Void
}

extension FocusedValues {
    @Entry var pluginManagementActions: MacPluginManagementActions?
}

struct MacPluginManagementCommands: Commands {
    @FocusedValue(\.pluginManagementActions) private var actions

    var body: some Commands {
        if let actions {
            CommandMenu("插件") {
                Button("添加订阅源", systemImage: "plus", action: actions.addSource)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!actions.canAddSource)

                Button("订阅源", systemImage: "list.bullet.rectangle", action: actions.showSources)
                    .disabled(!actions.canShowSources)

                Divider()

                Button("全部更新", action: actions.update)
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(!actions.canUpdate)
                Button("检查插件更新", action: actions.check)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!actions.canCheck)
            }
        }
    }
}
