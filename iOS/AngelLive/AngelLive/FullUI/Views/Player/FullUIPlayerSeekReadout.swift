#if canImport(KSPlayer)
import AngelLiveDependencies
import SwiftUI
import UIKit

struct FullUIPlayerSeekReadout: View {
    let time: Double
    let duration: Double
    let preview: SeekPreviewState
    let isHorizontalVideo: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(fullUIPlayerTime(time))
                .foregroundStyle(.white)
            Text(" / \(fullUIPlayerTime(duration))")
                .foregroundStyle(.white.opacity(0.68))
        }
        .font(.system(size: 28, weight: .semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .fullUIPlayerMediaText()
        .overlay(alignment: .top) {
            previewImage
                .alignmentGuide(.top) { $0[VerticalAlignment.bottom] + 8 }
        }
        .padding(.horizontal, FullUIPlayerChrome.inset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var previewImage: some View {
        ZStack {
            Color.black
            switch preview {
            case .frame(let image, let actualTime):
                Image(uiImage: UIImage(cgImage: image)).resizable().scaledToFit()
                if abs(actualTime - time) > 0.5 {
                    Text("预览约 \(fullUIPlayerTime(actualTime))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(4)
                        .background(.black.opacity(0.7), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            case .unavailable:
                Text("暂无法预览").font(.caption).foregroundStyle(.white.opacity(0.8))
            case .idle, .loading:
                ProgressView().tint(.white)
            }
        }
        .frame(width: isHorizontalVideo ? 128 : 72, height: isHorizontalVideo ? 72 : 128)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
#endif
