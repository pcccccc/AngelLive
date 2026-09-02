import Observation
import UIKit

@MainActor
@Observable
final class TVAppIconSettingsModel {
    enum Choice: String, CaseIterable, Identifiable {
        case primary
        case xiaoShengBiBi

        var id: Self { self }

        var title: String {
            switch self {
            case .primary: "默认"
            case .xiaoShengBiBi: "小声逼逼"
            }
        }

        var alternateIconName: String? {
            switch self {
            case .primary: nil
            case .xiaoShengBiBi: "XiaoShengBB"
            }
        }

        var previewAssetName: String {
            switch self {
            case .primary: "App Icon"
            case .xiaoShengBiBi: "XiaoShengBBPreview"
            }
        }
    }

    var selection: Choice
    var applyingChoice: Choice?
    var isShowingError = false
    var errorMessage = ""

    init() {
        let application = UIApplication.shared
        selection = application.alternateIconName == Choice.xiaoShengBiBi.alternateIconName
            ? .xiaoShengBiBi
            : .primary
    }

    func select(_ choice: Choice) async {
        let application = UIApplication.shared
        guard choice != selection, applyingChoice == nil else { return }
        guard application.supportsAlternateIcons else {
            showError("当前安装包不支持备用应用图标。")
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
