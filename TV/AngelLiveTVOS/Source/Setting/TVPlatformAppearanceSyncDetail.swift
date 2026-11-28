import AngelLiveCore
import AngelLiveDependencies
import SwiftUI

struct TVPlatformAppearanceSyncDetail: View {
    let onBack: () -> Void
    @Environment(\.usesFullUI) private var usesFullUI
    @ObservedObject private var master = PlatformCredentialSyncService.shared
    @AppStorage(PlatformAppearanceSyncService.settingKey) private var enabled = true
    private let status = PlatformAppearanceSyncService.status

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("配置页外观同步")
                    .font(.system(size: 30, weight: .bold))
                    .accessibilityAddTraits(.isHeader)

                Button {
                    enabled.toggle()
                } label: {
                    TVAppearanceControlLabel("iCloud 外观同步", value: Text(enabled ? "已开启" : "已关闭"), hasChevron: false)
                }
                .disabled(!master.iCloudSyncEnabled)
                .accessibilityIdentifier("platform.appearance.sync.toggle")

                Button {
                    Task { await PlatformAppearanceSyncService.shared.sync() }
                } label: {
                    TVAppearanceControlLabel("立即同步外观", value:
                        PlatformAppearanceSyncStateLabel(enabled: enabled, masterEnabled: master.iCloudSyncEnabled),
                        hasChevron: false)
                }
                .disabled(!master.iCloudSyncEnabled || !enabled || status.isSyncing)
                .accessibilityIdentifier("platform.appearance.sync.now")

                Button("返回", systemImage: "chevron.left", action: onBack)
            }
            .padding(.bottom, 24)
        }
        .scrollClipDisabled()
        .onExitCommand(perform: usesFullUI ? nil : onBack)
        .tvFullUIBackCommand(enabled: usesFullUI, perform: onBack)
    }
}
