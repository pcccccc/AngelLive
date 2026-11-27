import Testing
@testable import AngelLiveCore

@Test func sessionSummaryResolvesUserFacingPlatformNames() {
    let id = "fixture.plugin"
    let installed = SandboxPluginMetadata(pluginId: id, version: "1", displayName: "本地名称", liveTypes: [])
    let runtime = LiveParseJSPlatform(pluginId: id, liveTypes: [], platformName: "  显示名称  ")
    #expect(SessionPlatformNames(platforms: [runtime], installed: [id: installed]).displayName(for: id) == "显示名称")
    #expect(SessionPlatformNames(platforms: [], installed: [id: installed]).displayName(for: id) == "本地名称")
    let unnamed = LiveParseJSPlatform(pluginId: id, liveTypes: [], platformName: id)
    #expect(SessionPlatformNames(platforms: [unnamed], installed: [:]).displayName(for: id) == "未命名插件")
    #expect(SessionPlatformNames(platforms: [], installed: [:]).displayName(for: "source-a") == "未安装插件")
}
