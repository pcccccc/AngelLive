import SwiftUI

public extension PlatformGridDensity {
    var appearanceTitle: LocalizedStringKey {
        switch self {
        case .comfortable: "舒展"
        case .standard: "标准"
        case .compact: "紧凑"
        }
    }
}

public extension PlatformCardAspectPreset {
    var appearanceTitle: LocalizedStringKey {
        switch self {
        case .wide: "16:9"
        case .classic: "5:3"
        case .compact: "2:1"
        case .square: "1:1"
        }
    }
}

public extension PlatformBackgroundStyle {
    static var appearancePresets: [Self] {
        [.defaultAsset, .dominantIconAura, .systemSurface] + PlatformBackgroundPreset.allCases.map(Self.preset)
    }

    var appearanceTitle: LocalizedStringKey {
        switch self {
        case .defaultAsset: "默认底图"
        case .dominantIconAura: "微染底色"
        case .systemSurface: "纯净卡片"
        case .preset(.graphite): "深灰石板"
        case .preset(.ocean): "暮色深蓝"
        case .preset(.dusk): "暗夜紫灰"
        case .preset(.forest): "松影深绿"
        case .preset(.ember): "暖褐暗调"
        case .customImage: "自定义图片"
        }
    }
}

public extension PlatformTitleVisibility {
    var appearanceTitle: LocalizedStringKey {
        switch self {
        case .auto: "自动"
        case .always: "始终显示"
        case .hidden: "隐藏"
        }
    }
}

public extension PlatformLogoMode {
    var appearanceTitle: LocalizedStringKey {
        switch self {
        case .auto: "自动"
        case .symbol: "系统符号"
        case .monogramBadge: "缩写徽章"
        case .customImage: "自定义图片"
        }
    }
}

public enum PlatformAppearanceOptions {
    public struct Symbol: Identifiable, Sendable {
        public let id: String
        public let title: LocalizedStringResource
    }

    public static let symbols: [Symbol] = [
        .init(id: "tv", title: "电视"),
        .init(id: "trophy.fill", title: "赛事"),
        .init(id: "film.fill", title: "影视"),
        .init(id: "leaf.fill", title: "自然"),
        .init(id: "radio.fill", title: "电台"),
        .init(id: "music.note", title: "音乐"),
        .init(id: "gamecontroller.fill", title: "游戏"),
        .init(id: "book.closed.fill", title: "人文"),
        .init(id: "globe", title: "国际"),
        .init(id: "antenna.radiowaves.left.and.right", title: "频道"),
        .init(id: "list.and.film", title: "片单"),
        .init(id: "square.stack.fill", title: "专题")
    ]

    public struct Accent: Identifiable, Sendable {
        public let id: String
        public let title: LocalizedStringResource
    }

    public static let accents: [Accent] = [
        .init(id: "#3B6E8C", title: "雾蓝"),
        .init(id: "#C85A3B", title: "赤陶"),
        .init(id: "#4D7C6F", title: "松绿"),
        .init(id: "#575989", title: "靛灰"),
        .init(id: "#9C6B3B", title: "琥珀"),
        .init(id: "#6D597A", title: "烟紫"),
        .init(id: "#4B5563", title: "石板灰"),
        .init(id: "#007AFF", title: "系统蓝")
    ]
}

public struct PlatformAppearanceSyncStateLabel: View {
    let enabled: Bool
    let masterEnabled: Bool
    private let status = PlatformAppearanceSyncService.status

    public init(enabled: Bool, masterEnabled: Bool) {
        self.enabled = enabled
        self.masterEnabled = masterEnabled
    }

    public var body: some View { message }

    public var message: Text {
        if !masterEnabled {
            Text("iCloud 总开关已关闭")
        } else if !enabled {
            Text("已关闭")
        } else if status.isSyncing {
            Text("正在同步")
        } else if status.outcome == .accountUnavailable {
            Text("iCloud 账号不可用")
        } else if status.outcome == .failed {
            Text("同步失败")
        } else if let date = status.lastSuccessfulSync {
            Text("上次同步 \(date, style: .relative)前")
        } else {
            Text("等待同步")
        }
    }
}
