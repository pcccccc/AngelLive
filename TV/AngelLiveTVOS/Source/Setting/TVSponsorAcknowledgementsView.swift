import CoreImage.CIFilterBuiltins
import SharedAssets
import SwiftUI

struct TVSponsorAcknowledgementsView: View {
    let onClose: () -> Void
    @FocusState private var backButtonFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("赞助商")
                    .font(.system(size: 57, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(SponsorAcknowledgements.introduction)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            TVSponsorAcknowledgementsList()
                .frame(maxHeight: .infinity)

            Button("返回", action: onClose)
                .focused($backButtonFocused)
                .padding(.top, 16)
        }
        .frame(maxWidth: 1500, maxHeight: .infinity)
        .defaultFocus($backButtonFocused, true)
    }
}

private struct TVSponsorAcknowledgementsList: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 60) {
                TVSponsorQRCodeCard(
                    image: TVSponsorQRCodes.packyCode,
                    caption: "注册 PackyCode"
                )
                TVPackyCodeSponsorContent()
            }

            Divider()
                .padding(.vertical, 38.4)

            HStack(alignment: .top, spacing: 60) {
                TVSponsorQRCodeCard(
                    image: TVSponsorQRCodes.ksPlayer,
                    caption: "查看 KSPlayer 项目"
                )
                TVKSPlayerSponsorContent()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TVPackyCodeSponsorContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image.shared(SponsorAcknowledgements.packyCodeBanner)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(height: 64)
                .foregroundStyle(.primary)
                .accessibilityLabel("PackyCode")
                .accessibilityAddTraits(.isHeader)
            Text(SponsorAcknowledgements.packyCodeThanks)
                .font(.headline)
            Text(SponsorAcknowledgements.packyCodeDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TVKSPlayerSponsorContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "KSPlayer")
                .font(.system(size: 48, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(SponsorAcknowledgements.ksPlayerAcknowledgement)
                .font(.headline)
            Text(SponsorAcknowledgements.ksPlayerThanks)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TVSponsorQRCodeCard: View {
    let image: UIImage?
    let caption: LocalizedStringKey

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                }
            }
            .padding(12)
            .frame(width: 250, height: 250)
            .background(Color.white)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityLabel("二维码")

            Text(caption)
                .font(.system(size: 27, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("使用手机相机扫描二维码")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 250)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

private enum TVSponsorQRCodes {
    static let packyCode = makeImage(for: SponsorAcknowledgements.packyCodeURL)
    static let ksPlayer = makeImage(for: SponsorAcknowledgements.ksPlayerURL)

    private static func makeImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage else { return nil }

        // 在模块坐标中补足白色静区，视图仍沿用 250pt / 12pt 的既有规格。
        let extent = output.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: .white).cropped(to: extent)
        let code = output.composited(over: white)
            .cropped(to: extent)
            .transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let image = CIContext().createCGImage(code, from: code.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
