import SwiftUI

struct MacPluginManagementActions {
    let canUpdate: Bool
    let canCheck: Bool
    let update: () -> Void
    let check: () -> Void
}

private struct MacPluginManagementActionsKey: FocusedValueKey {
    typealias Value = MacPluginManagementActions
}

extension FocusedValues {
    var pluginManagementActions: MacPluginManagementActions? {
        get { self[MacPluginManagementActionsKey.self] }
        set { self[MacPluginManagementActionsKey.self] = newValue }
    }
}

struct MacPluginManagementCommands: Commands {
    @FocusedValue(\.pluginManagementActions) private var actions

    var body: some Commands {
        if let actions {
            CommandMenu("插件") {
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
