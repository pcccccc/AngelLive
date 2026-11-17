import SwiftUI
import AngelLiveCore

struct TVPluginManagementIcon: View {
    let pluginID: String
    let name: String
    var remote: LiveParseRemotePluginItem? = nil
    let size: CGFloat
    var width: CGFloat? = nil
    var revision: UInt = 0
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loaded = false

    private var remoteURL: URL? {
        [remote?.tvosIcon, remote?.icon].compactMap { value -> URL? in
            guard let value, let url = URL(string: value),
                  ["https", "http"].contains(url.scheme ?? "") else { return nil }
            return url
        }.first
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if !loaded {
                ProgressView()
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fit)
                    case .empty: ProgressView()
                    case .failure: PluginManagementMonogram(pluginID: pluginID, displayName: name, size: size)
                    @unknown default: PluginManagementMonogram(pluginID: pluginID, displayName: name, size: size)
                    }
                }
            } else {
                PluginManagementMonogram(pluginID: pluginID, displayName: name, size: size)
            }
        }
        .frame(width: width ?? size, height: size)
        .accessibilityHidden(true)
        .task(id: [pluginID, String(revision), String(Double(size)), String(Double(width ?? size)), String(Double(displayScale))]) {
            image = TVPlatformIconProvider.managementImage(
                pluginID: pluginID, targetSize: CGSize(width: width ?? size, height: size),
                displayScale: displayScale, remote: remote)
            loaded = true
        }
    }
}
