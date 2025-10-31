//
//  Constants.swift
//  AngelLive
//
//  Created by pangchong on 10/19/25.
//

import SwiftUI

/// 格式化人气数字
/// - Parameter count: 人气数
/// - Returns: 格式化后的字符串（如：1.2万、10.5万）
func formatPopularity(_ count: String) -> String {
    guard let number = Int(count) else { return count }
    if number >= 10000 {
        let wan = Double(number) / 10000.0
        return String(format: "%.1f万", wan)
    } else if number >= 1000 {
        let k = Double(number) / 1000.0
        return String(format: "%.1fk", k)
    } else {
        return "\(number)"
    }
}

/// 应用全局常量定义
enum AppConstants {

    // MARK: - Color System

    /// 颜色系统 - 统一管理应用中的所有颜色
    enum Colors {

        // MARK: - Text Colors (文本颜色)

        /// 一级文本颜色 - 用于主标题、重要文本
        static let primaryText = Color.primary

        /// 二级文本颜色 - 用于副标题、次要文本
        static let secondaryText = Color.secondary

        /// 三级文本颜色 - 用于描述文本、辅助信息
        static let tertiaryText = Color(.tertiaryLabel)

        /// 占位符文本颜色
        static let placeholderText = Color.secondary.opacity(0.6)

        // MARK: - Background Colors (背景颜色)

        /// 主背景 - 使用系统自适应背景
        static let primaryBackground = Color(.systemBackground)

        /// 次要背景 - 用于卡片、分组背景
        static let secondaryBackground = Color(.secondarySystemBackground)

        /// 三级背景 - 用于嵌套内容背景
        static let tertiaryBackground = Color(.tertiarySystemBackground)

        /// 毛玻璃材质背景 - 用于浮层、卡片等
        static let materialBackground = Material.ultraThinMaterial

        /// 分组背景 - 用于 Form、List 的分组背景
        static let groupedBackground = Color(.systemGroupedBackground)

        // MARK: - Accent Colors (强调色)

        /// 主题色 - 应用主色调
        static let accent = Color.accentColor

        /// 链接/交互色
        static let link = Color.blue

        /// 成功/正向状态
        static let success = Color.green

        /// 警告状态
        static let warning = Color.orange

        /// 错误/危险状态
        static let error = Color.red

        /// 信息提示
        static let info = Color.blue

        // MARK: - Border & Separator Colors (边框和分割线颜色)

        /// 一级边框颜色 - 用于主要边框
        static let primaryBorder = Color.primary.opacity(0.2)

        /// 二级边框颜色 - 用于次要边框
        static let secondaryBorder = Color.secondary.opacity(0.2)

        /// 分割线颜色
        static let separator = Color(.separator)

        /// 轻度分割线
        static let lightSeparator = Color(.separator).opacity(0.5)

        // MARK: - Shadow Colors (阴影颜色)

        /// 主阴影颜色
        static let primaryShadow = Color.primary.opacity(0.1)

        /// 次要阴影颜色
        static let secondaryShadow = Color.primary.opacity(0.05)

        // MARK: - Overlay Colors (遮罩颜色)

        /// 暗色遮罩 - 用于图片上的文字背景等
        static let darkOverlay = Color.black.opacity(0.3)

        /// 亮色遮罩
        static let lightOverlay = Color.white.opacity(0.3)

        // MARK: - Specific Use Colors (特定用途颜色)

        /// 直播状态 - 正在直播
        static let liveStatus = Color.green

        /// 离线状态
        static let offlineStatus = Color.gray

        /// 卡片背景渐变色（用于占位符等）
        static func placeholderGradient() -> LinearGradient {
            LinearGradient(
                colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Spacing System

    /// 间距系统 - 统一管理应用中的间距
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    /// 圆角系统 - 统一管理应用中的圆角
    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let round: CGFloat = 999 // 完全圆角
    }

    // MARK: - Shadow

    /// 阴影系统
    enum Shadow {
        static let sm = (color: AppConstants.Colors.primaryShadow, radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let md = (color: AppConstants.Colors.primaryShadow, radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let lg = (color: AppConstants.Colors.primaryShadow, radius: CGFloat(10), x: CGFloat(0), y: CGFloat(5))
    }
    
    enum AspectRatio {
        static let pic = 16.0 / 9.0

        /// 根据卡片宽度和设备类型计算合适的宽高比
        /// - Parameters:
        ///   - cardWidth: 卡片宽度
        /// - Returns: 卡片的宽高比
        static func card(width cardWidth: CGFloat) -> CGFloat {
            // 封面图高度 = 宽度 / (16/9)
            let coverHeight = cardWidth / pic

            // 主播信息区域高度：头像(32)
            let infoHeight: CGFloat = 32

            // 内边距
            let padding: CGFloat = 8

            // 总高度
            let totalHeight = coverHeight + infoHeight + padding

            // 返回宽高比 (宽度/高度)
            return cardWidth / totalHeight
        }
    }

    // MARK: - Device Detection

    /// 设备类型检测
    enum Device {
        /// 是否为 iPad
        static var isIPad: Bool {
            UIDevice.current.userInterfaceIdiom == .pad
        }

        /// 是否为 iPhone
        static var isIPhone: Bool {
            UIDevice.current.userInterfaceIdiom == .phone
        }

        /// 是否为 Apple TV
        static var isTV: Bool {
            UIDevice.current.userInterfaceIdiom == .tv
        }
    }
}

// MARK: - Convenience Extensions

extension Color {
    /// 快速访问应用颜色
    static let appPrimaryText = AppConstants.Colors.primaryText
    static let appSecondaryText = AppConstants.Colors.secondaryText
    static let appTertiaryText = AppConstants.Colors.tertiaryText
    static let appPrimaryBorder = AppConstants.Colors.primaryBorder
    static let appSecondaryBorder = AppConstants.Colors.secondaryBorder
}
