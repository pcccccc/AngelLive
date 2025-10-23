//
//  BlurredBackgroundView.swift
//  AngelLive
//
//  Created by pangchong on 10/23/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 模糊背景视图（使用主播头像）
struct BlurredBackgroundView: View {
    let imageURL: String

    var body: some View {
        GeometryReader { geometry in
            // 主播头像模糊背景
            KFImage(URL(string: imageURL))
                .placeholder {
                    // 占位渐变色
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.3),
                            Color.blue.opacity(0.3),
                            Color.pink.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .blur(radius: 60) // 强烈模糊，创造渐变效果
                .scaleEffect(1.2) // 放大避免边缘问题
                .overlay {
                    Color.black.opacity(0.2)
                        .blendMode(.darken)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            
        }
    }
}

#Preview {
    BlurredBackgroundView(imageURL: "https://example.com/avatar.jpg")
}
