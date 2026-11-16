import SharedAssets
import SwiftUI

struct SponsorAcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                PackyCodeSponsorContent()
                SponsorWebsiteRow(
                    title: SponsorAcknowledgements.packyCodeLinkLabel,
                    destination: SponsorAcknowledgements.packyCodeURL
                )
            } header: {
                Text(SponsorAcknowledgements.introduction)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .textCase(nil)
            }

            Section {
                KSPlayerSponsorContent()
                SponsorWebsiteRow(
                    title: SponsorAcknowledgements.ksPlayerLinkLabel,
                    destination: SponsorAcknowledgements.ksPlayerURL
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("赞助商")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PackyCodeSponsorContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image.shared(SponsorAcknowledgements.packyCodeBanner)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(height: 24)
                .foregroundStyle(.primary)
                .accessibilityLabel("PackyCode")
                .accessibilityAddTraits(.isHeader)
            Text(SponsorAcknowledgements.packyCodeThanks)
                .font(.headline)
            Text(SponsorAcknowledgements.packyCodeDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct KSPlayerSponsorContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "KSPlayer")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(SponsorAcknowledgements.ksPlayerAcknowledgement)
                .font(.headline)
            Text(SponsorAcknowledgements.ksPlayerThanks)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SponsorWebsiteRow: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack {
                Text(title)
                    .foregroundStyle(SharedAssets.Colors.appAccent)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
        }
        .tint(SharedAssets.Colors.appAccent)
    }
}
