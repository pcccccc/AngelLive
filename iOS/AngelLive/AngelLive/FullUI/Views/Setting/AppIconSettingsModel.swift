import Observation
import UIKit

@MainActor
@Observable
final class AppIconSettingsModel {
    enum Choice: String, CaseIterable, Identifiable {
        case xiaoShengBiBi
        case classic

        var id: Self { self }

        var title: String {
            switch self {
            case .xiaoShengBiBi: "小声逼逼（联名）"
            case .classic: "AngelLive 原版"
            }
        }

        var alternateIconName: String? {
            switch self {
            case .xiaoShengBiBi: nil
            case .classic: "AngelLiveClassic"
            }
        }

        var previewAssetName: String {
            switch self {
            case .xiaoShengBiBi: "XiaoShengBBPreview"
            case .classic: "icon"
            }
        }
    }

    var selection: Choice
    var applyingChoice: Choice?
    var isShowingError = false
    var errorMessage = ""

    init() {
        let application = UIApplication.shared
        // Both the bundle default and the legacy XiaoShengBB alternate use
        // the collaboration artwork, including after an app update.
        selection = application.alternateIconName == Choice.classic.alternateIconName
            ? .classic
            : .xiaoShengBiBi
    }

    func select(_ choice: Choice) async {
        let application = UIApplication.shared
        guard choice != selection, applyingChoice == nil else { return }
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
