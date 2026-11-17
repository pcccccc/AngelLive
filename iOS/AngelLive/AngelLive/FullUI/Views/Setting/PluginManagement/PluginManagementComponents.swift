import SwiftUI
import UIKit
import AngelLiveCore
import Observation

@MainActor
@Observable
final class PluginManagementFeedback {
    var recentSuccessIDs: Set<String> = []
    var recentInstallIDs: Set<String> = []
}

struct ManagedPluginItem: Identifiable {
    enum Namespace { case installed, catalog }
    let pluginID: String
    let name: String
    let sourceURL: String?
    let remote: RemotePluginDisplayItem?
    var namespace: Namespace = .catalog
    var id: String {
        switch namespace {
        case .installed: "installed:\(pluginID)"
        case .catalog: "catalog:\(sourceURL ?? "unresolved"):\(pluginID)"
        }
    }
}

struct PluginManagementSectionHeading: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    var subtitle: LocalizedStringKey? = nil
    var actionTitle: LocalizedStringKey? = nil
    var actionDisabled = false
    var action: (() -> Void)? = nil
    var includesSectionSpacing = false
    private var hasAccessory: Bool { subtitle != nil || (actionTitle != nil && action != nil) }
    var body: some View {
        let metrics = PluginManagementTextMetrics(text: title, style: .sectionTitle, locale: locale, dynamicTypeSize: dynamicTypeSize)
        ViewThatFits(in: .horizontal) {
            PluginManagementHeadingGap(inkAscent: metrics.inkBounds.maxY, sectionSpacing: PluginManagementLayout.sectionSpacing, includesSectionSpacing: includesSectionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    PluginManagementEdgeText(text: title, style: .sectionTitle).foregroundStyle(PluginManagementLayout.primaryText)
                    Spacer(minLength: PluginManagementLayout.itemSpacing)
                    if hasAccessory {
                        PluginManagementHeadingAccessory(subtitle: subtitle, actionTitle: actionTitle, disabled: actionDisabled, action: action)
                    }
                }
            }
            PluginManagementHeadingGap(inkAscent: metrics.inkBounds.maxY, sectionSpacing: PluginManagementLayout.sectionSpacing, includesSectionSpacing: includesSectionSpacing) {
                VStack(alignment: .leading, spacing: PluginManagementLayout.itemSpacing) {
                    PluginManagementEdgeText(text: title, style: .sectionTitle).foregroundStyle(PluginManagementLayout.primaryText)
                    if hasAccessory {
                        PluginManagementHeadingAccessory(subtitle: subtitle, actionTitle: actionTitle, disabled: actionDisabled, action: action)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .frame(minHeight: includesSectionSpacing ? nil : PluginManagementLayout.minimumTarget, alignment: .bottom)
        .textCase(nil)
        .padding(.bottom, PluginManagementLayout.headerToCard)
        .listRowInsets(PluginManagementLayout.zeroInsets)
    }
}

private struct PluginManagementHeadingAccessory: View {
    let subtitle: LocalizedStringKey?
    let actionTitle: LocalizedStringKey?
    let disabled: Bool
    let action: (() -> Void)?
    var body: some View {
        Group {
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .frame(minHeight: PluginManagementLayout.minimumTarget, alignment: .bottom)
                        .contentShape(Rectangle())
                }.disabled(disabled)
                    .accessibilityIdentifier("plugins.installAll")
            } else if let subtitle {
                Text(subtitle).foregroundStyle(PluginManagementLayout.secondaryText)
            }
        }.font(.subheadline).tint(PluginManagementLayout.primaryAction)
    }
}

struct PluginManagementToolIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.body).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct PluginManagementIcon: View {
    @Environment(PluginAvailabilityService.self) private var availability
    @Environment(\.displayScale) private var displayScale
    let pluginID: String
    let displayName: String
    var remoteIcon: String? = nil
    var size: CGFloat = PluginManagementLayout.iconSize
    @State private var image: UIImage?
    @State private var isLoading = true
    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: size, height: size)
            } else if isLoading {
                RoundedRectangle(cornerRadius: size * PluginManagementLayout.iconRadius / PluginManagementLayout.iconSize, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill).opacity(0.45))
                Image(systemName: "puzzlepiece.extension.fill").resizable().scaledToFit()
                    .foregroundStyle(PluginManagementLayout.secondaryText).padding(size * 0.22)
            } else {
                PluginManagementMonogram(pluginID: pluginID, displayName: displayName, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * PluginManagementLayout.iconRadius / PluginManagementLayout.iconSize, style: .continuous))
        .accessibilityHidden(true)
        .task(id: [pluginID, String(availability.catalogRevision), remoteIcon ?? "", String(Double(size)), String(Double(displayScale))]) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard !Task.isCancelled else { return }
        image = nil
        isLoading = true
        if let platform = LiveParseJSPlatformManager.availablePlatforms.first(where: { $0.pluginId == pluginID }),
           let local = PlatformIconProvider.pluginManagementImage(
               for: platform.liveType, targetSide: size, displayScale: displayScale
           ), local.cgImage != nil {
            image = local
            isLoading = false
            return
        }
        guard let remoteIcon, let url = URL(string: remoteIcon), ["http", "https"].contains(url.scheme ?? "") else {
            isLoading = false
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
                isLoading = false
                return
            }
            let remote = UIImage(data: data)
            image = remote?.cgImage == nil ? nil : remote
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }
}

struct PluginInstallConsentPanel: View {
    @Environment(PluginInstallConsentService.self) private var consent
    let hostID: UUID
    var body: some View {
        if consent.isPresenting(for: hostID) {
            VStack(alignment: .leading, spacing: 12) {
                Text(consent.alertTitle).font(.headline)
                Text(consent.alertMessage).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits {
                    HStack {
                        Button(consent.cancelButtonTitle) { consent.resolve(false) }.buttonStyle(.bordered)
                        Button(consent.continueButtonTitle) { consent.resolve(true) }.buttonStyle(.borderedProminent)
                    }
                    VStack(alignment: .leading) {
                        Button(consent.cancelButtonTitle) { consent.resolve(false) }.buttonStyle(.bordered)
                        Button(consent.continueButtonTitle) { consent.resolve(true) }.buttonStyle(.borderedProminent)
                    }
                }.controlSize(.large)
            }.padding(PluginManagementLayout.contentInset).accessibilityElement(children: .contain)
                .transition(.opacity)
        }
    }
}

struct PluginManagementEmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringResource
    var isLoading = false
    var actionTitle: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: PluginManagementLayout.itemSpacing) {
            if isLoading { ProgressView().accessibilityHidden(true) }
            Text(title).font(.headline).foregroundStyle(PluginManagementLayout.primaryText)
            Text(message).font(.subheadline).foregroundStyle(PluginManagementLayout.secondaryText)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.large)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        .padding(.horizontal, PluginManagementLayout.contentInset)
        .padding(.vertical, PluginManagementLayout.detailSpacing)
        .background(PluginManagementLayout.cardBackground, in: RoundedRectangle(cornerRadius: PluginManagementLayout.cardRadius, style: .continuous))
        .tint(PluginManagementLayout.primaryAction)
    }
}

struct PluginUninstallUndoBar: View {
    let name: String
    let deadline: Date?
    let undo: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text("已卸载 \(name)").font(.subheadline).lineLimit(2)
            Spacer(minLength: 0)
            Button(action: undo) {
                HStack(spacing: 8) {
                    if let deadline {
                        ProgressView(timerInterval: deadline.addingTimeInterval(-5)...deadline, countsDown: true) { EmptyView() }
                            .progressViewStyle(.circular).labelsHidden().frame(width: 18, height: 18)
                    }
                    Text("撤销").font(.subheadline.weight(.semibold))
                }.frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("撤销卸载 \(name)")
        }.padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .accessibilityElement(children: .contain)
    }
}

func pluginSourceHost(_ url: String) -> String { URL(string: url)?.host() ?? url }

struct FullUIPluginSourceErrorCard: View {
    let title: LocalizedStringKey
    let message: String
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(SupportDiagnosticSanitizer.text(message)).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
    }
}

struct PluginSourceHealthLabel: View {
    let health: PluginSourceHealth
    var body: some View {
        HStack(spacing: 5) {
            if case .checking = health { ProgressView().controlSize(.mini) }
            else { Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true) }
            Text(title).foregroundStyle(.secondary)
        }.font(.footnote).accessibilityElement(children: .combine)
    }
    private var title: LocalizedStringResource {
        switch health {
        case .unknown: "尚未检查"
        case .checking: "正在检查…"
        case .healthy(let count): "正常 · \(count) 个插件"
        case .failed: "来源异常"
        }
    }
    private var symbol: String {
        switch health {
        case .healthy: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        default: "questionmark.circle"
        }
    }
    private var color: Color { if case .healthy = health { .green } else if case .failed = health { .orange } else { .secondary } }
}
