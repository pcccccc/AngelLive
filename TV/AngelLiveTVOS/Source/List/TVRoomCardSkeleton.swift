import SwiftUI
import AngelLiveDependencies

/// 与 `LiveCardView` 未聚焦时的轮廓一致：370×210 封面、圆角 12、44 头像。
/// 填色与房间列表骨架一致，半透明，让列表根上的薄材质继续透出。
struct TVRoomCardSkeleton: View {
    var fill: Color = Color.gray.opacity(0.3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(fill)
                .frame(width: 370, height: 210)

            HStack(spacing: 12) {
                Circle()
                    .fill(fill)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fill)
                        .frame(width: 160, height: 20)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fill)
                        .frame(width: 220, height: 15)
                }
            }
        }
        .padding(.top, 8)
        .frame(width: 370, height: 280, alignment: .top)
        .accessibilityHidden(true)
    }
}

struct TVRoomSkeletonGrid: View {
    let columns: [GridItem]
    let spacing: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            skeletonGrid(fill: Color.gray.opacity(0.3))
            if !reduceMotion {
                skeletonGrid(fill: Color.white.opacity(0.35))
                    .shimmering()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载")
        .focusable(false)
    }

    private func skeletonGrid(fill: Color) -> some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
            ForEach(0..<8, id: \.self) { _ in
                TVRoomCardSkeleton(fill: fill)
            }
        }
    }
}
