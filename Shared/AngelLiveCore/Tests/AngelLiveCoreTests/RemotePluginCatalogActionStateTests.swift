import Testing
@testable import AngelLiveCore

@Suite("Remote plugin catalog action state")
struct RemotePluginCatalogActionStateTests {
    private struct Case: Sendable {
        let installState: PluginInstallState
        let installed: Bool
        let hasUpdate: Bool
        let updating: Bool
        let expected: RemotePluginCatalogActionState
    }

    @Test("catalog state resolves from installation facts", arguments: [
        Case(installState: .installed, installed: true, hasUpdate: true, updating: false, expected: .update),
        Case(installState: .notInstalled, installed: true, hasUpdate: true, updating: false, expected: .update),
        Case(installState: .installed, installed: true, hasUpdate: false, updating: false, expected: .installed),
        Case(installState: .notInstalled, installed: true, hasUpdate: false, updating: false, expected: .installed),
        Case(installState: .installed, installed: true, hasUpdate: true, updating: true, expected: .updating),
        Case(installState: .installing, installed: false, hasUpdate: false, updating: false, expected: .installing),
        Case(installState: .notInstalled, installed: false, hasUpdate: false, updating: false, expected: .install),
        Case(installState: .failed("network"), installed: false, hasUpdate: false, updating: false, expected: .failed("network"))
    ])
    private func resolvesCatalogState(_ testCase: Case) {
        #expect(
            resolve(
                testCase.installState,
                installed: testCase.installed,
                hasUpdate: testCase.hasUpdate,
                updating: testCase.updating
            ) == testCase.expected
        )
    }

    private func resolve(
        _ installState: PluginInstallState,
        installed: Bool,
        hasUpdate: Bool = false,
        updating: Bool = false
    ) -> RemotePluginCatalogActionState {
        .resolve(
            installState: installState,
            isInstalled: installed,
            hasUpdate: hasUpdate,
            isUpdating: updating
        )
    }
}
