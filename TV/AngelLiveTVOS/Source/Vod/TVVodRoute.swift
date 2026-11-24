import AngelLiveCore

@MainActor
enum TVVodRoute {
    static func matches(room: LiveModel, appViewModel: AppState) -> Bool {
        appViewModel.pluginAvailability.hasAvailablePlugins && VodHostRouting.declaresVod(room)
    }
}
