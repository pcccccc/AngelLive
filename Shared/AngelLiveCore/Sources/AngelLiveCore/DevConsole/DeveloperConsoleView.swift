import SwiftUI

@available(iOS 17.0, macOS 14.0, tvOS 17.0, *)
public struct DeveloperConsoleView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case plugin = "插件请求"
        case playback = "播放时间轴"
        var id: Self { self }
    }

    private let onClose: (() -> Void)?
    @State private var page: Page = .plugin

    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("控制台内容", selection: $page) {
                    ForEach(Page.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            switch page {
            case .plugin:
                PluginConsoleView()
            case .playback:
                PlaybackTimelineView()
            }
        }
    }
}
