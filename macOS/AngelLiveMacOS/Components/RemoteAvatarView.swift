import SwiftUI
import AppKit
import Kingfisher

struct RemoteAvatarView<Placeholder: View>: View {
    let url: URL?
    let size: CGFloat
    let placeholder: Placeholder

    @State private var loadState: LoadState = .idle

    init(url: URL?, size: CGFloat, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.size = size
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            switch loadState {
            case .idle, .failed:
                placeholder
            case .staticImage(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .animated(let data, let cacheKey):
                KFAnimatedImage.data(data, cacheKey: cacheKey)
                    .configure { view in
                        view.framePreloadCount = 2
                    }
                    .placeholder { placeholder }
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: url?.absoluteString) {
            await resolveImage()
        }
    }

    @MainActor
    private func resolveImage() async {
        guard let url else {
            loadState = .failed
            return
        }

        loadState = .idle

        do {
            let data = try await RemoteAvatarDataLoader.shared.data(for: url)
            try Task.checkCancellation()

            if data.kf.imageFormat == .GIF {
                loadState = .animated(data: data, cacheKey: url.absoluteString)
                return
            }

            guard let image = NSImage(data: data) else {
                loadState = .failed
                return
            }

            loadState = .staticImage(image)
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed
        }
    }

    private enum LoadState {
        case idle
        case staticImage(NSImage)
        case animated(data: Data, cacheKey: String)
        case failed
    }
}

actor RemoteAvatarDataLoader {
    static let shared = RemoteAvatarDataLoader()

    private let cache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.countLimit = 256
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()
    private var inFlightTasks: [URL: Task<Data, Error>] = [:]

    func data(for url: URL) async throws -> Data {
        if let cachedData = cache.object(forKey: url as NSURL) {
            return cachedData as Data
        }

        if let task = inFlightTasks[url] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw URLError(.badServerResponse)
            }

            return data
        }

        inFlightTasks[url] = task
        defer { inFlightTasks[url] = nil }

        let data = try await task.value
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }
}
