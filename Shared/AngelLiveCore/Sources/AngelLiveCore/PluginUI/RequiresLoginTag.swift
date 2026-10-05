//
//  RequiresLoginTag.swift
//  AngelLiveCore
//
//  插件列表里"需登录"胶囊标签:醒目色背景 + 白字,
//  统一三端(iOS / macOS / tvOS)的提示样式。
//

import SwiftUI

/// 胶囊形状的"需登录"标签,跟随登录类插件出现在标题行。
public struct RequiresLoginTag: View {

    /// 标签尺寸预设,适配普通列表行和 tvOS 大字号场景。
    public enum Size: Sendable {
        case compact
        case regular

        var font: Font {
            switch self {
            case .compact: return .caption2.weight(.semibold)
            case .regular: return .system(size: 18, weight: .semibold)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .compact: return 6
            case .regular: return 12
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .compact: return 2
            case .regular: return 4
            }
        }
    }

    private let size: Size
    private let title: String

    public init(_ title: String = "需登录", size: Size = .compact) {
        self.title = title
        self.size = size
    }

    public var body: some View {
        Text(title)
            .font(size.font)
            .foregroundStyle(.white)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(Color.orange, in: Capsule())
            .accessibilityLabel(title)
    }
}
