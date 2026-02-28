#if !canImport(KSPlayer)

import Foundation
import SwiftUI
import Combine
import AngelLiveDependencies

public final class KSVideoPlayerModel: ObservableObject {
    @Published public var title: String
    public var config: KSVideoPlayer.Coordinator
    public var options: KSOptions
    @Published public var url: URL?

    public init(title: String, config: KSVideoPlayer.Coordinator, options: KSOptions, url: URL? = nil) {
        self.title = title
        self.config = config
        self.options = options
        self.url = url
    }
}

#endif
