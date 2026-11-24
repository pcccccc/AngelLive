import AngelLiveCore
import Observation
import UIKit

@MainActor
@Observable
final class AppIconSettingsModel {
    enum Choice: String, CaseIterable, Identifiable {
        case classic
        case xiaoShengBiBi

        var id: Self { self }

        var title: String {
            switch self {
            case .classic: "AngelLive 原版"
            case .xiaoShengBiBi: "小声逼逼（联名）"
            }
        }

        var alternateIconName: String? {
            switch self {
            case .classic: nil
            case .xiaoShengBiBi: "XiaoShengBB"
            }
        }

        var previewAssetName: String {
            switch self {
            case .classic: "icon"
            case .xiaoShengBiBi: "XiaoShengBBPreview"
            }
        }
    }

    var selection: Choice
    var applyingChoice: Choice?
    var isShowingError = false
    var errorMessage = ""
    let allowsSelection: Bool

    init() {
        #if DEBUG && canImport(KSPlayer)
        if VodDemoSandbox.isEnabled {
            allowsSelection = false
            selection = .classic
            return
        }
        #endif
        allowsSelection = true
        let application = UIApplication.shared
        // The bundle default and the legacy AngelLiveClassic alternate both use the original artwork.
        selection = application.alternateIconName == Choice.xiaoShengBiBi.alternateIconName
            ? .xiaoShengBiBi
            : .classic
    }

    func select(_ choice: Choice) async {
        guard allowsSelection else { return }
        let application = UIApplication.shared
        guard applyingChoice == nil, application.alternateIconName != choice.alternateIconName else { return }
        guard application.supportsAlternateIcons else {
            showError("当前设备或安装包不支持备用应用图标。")
            return
        }

        applyingChoice = choice
        defer { applyingChoice = nil }

        do {
            try await application.setAlternateIconName(choice.alternateIconName)
            selection = choice
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}
