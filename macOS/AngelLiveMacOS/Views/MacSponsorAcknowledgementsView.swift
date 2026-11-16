import AngelLiveCore
import SharedAssets
import SwiftUI

struct MacSponsorAcknowledgementsView: View {
    var body: some View {
        Form {
            Section {
                MacPackyCodeSponsorContent()
                MacSponsorWebsiteRow(
                    title: SponsorAcknowledgements.packyCodeLinkLabel,
                    destination: SponsorAcknowledgements.packyCodeURL
                )
            } header: {
                Text(SponsorAcknowledgements.introduction)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Section {
                MacKSPlayerSponsorContent()
                MacSponsorWebsiteRow(
                    title: SponsorAcknowledgements.ksPlayerLinkLabel,
                    destination: SponsorAcknowledgements.ksPlayerURL
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("赞助商")
        .macSettingsPage("赞助商")
    }
}

private struct MacPackyCodeSponsorContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image.shared(SponsorAcknowledgements.packyCodeBanner)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(height: 22)
                .foregroundStyle(.primary)
                .accessibilityLabel("PackyCode")
                .accessibilityAddTraits(.isHeader)
            Text(SponsorAcknowledgements.packyCodeThanks)
                .font(.headline)
            Text(SponsorAcknowledgements.packyCodeDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MacKSPlayerSponsorContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "KSPlayer")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(SponsorAcknowledgements.ksPlayerAcknowledgement)
                .font(.headline)
            Text(SponsorAcknowledgements.ksPlayerThanks)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MacSponsorWebsiteRow: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            PanelNavigationRow(title: title, showsChevron: false, titleColor: SharedAssets.Colors.appAccent) {
                Image(systemName: "safari")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            } trailing: {
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
