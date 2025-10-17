//
//  PlatformView.swift
//  AngelLive
//
//  Created by pangchong on 10/17/25.
//

import SwiftUI
import AngelLiveDependencies
import AngelLiveCore

struct PlatformView: View {
    @State private var viewModel = PlatformViewModel()
    @State private var selectedPlatform: Platformdescription?

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
                    ) {
                        ForEach(viewModel.platformInfo.indices, id: \.self) { index in
                            PlatformCard(platform: viewModel.platformInfo[index])
                                .onTapGesture {
                                    selectedPlatform = viewModel.platformInfo[index]
                                }
                        }
                    }
                    .padding()

                    Text("敬请期待更多平台...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical)
                }
            }
            .navigationTitle("平台")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: Binding(
                get: { selectedPlatform },
                set: { selectedPlatform = $0 }
            )) { platform in
                PlatformDetailView(platform: platform)
            }
        }
    }
}

// MARK: - Platform Card Component
struct PlatformCard: View {
    let platform: Platformdescription
    @State private var isPressed = false

    var body: some View {
        ZStack {
            // 背景图片
            if let image = UIImage(named: platform.bigPic) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .blur(radius: 4)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [
                            Color.blue.opacity(0.6),
                            Color.purple.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 180)
            }

            // 毛玻璃效果覆盖层
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .frame(height: 180)

            // 内容
            VStack(spacing: 12) {
                if let image = UIImage(named: platform.smallPic) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 60)
                } else {
                    Image(systemName: "play.tv")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                }

                Text(platform.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text(platform.descripiton)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
            .padding()
        }
        .frame(height: 180)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Platform Detail View
struct PlatformDetailView: View {
    let platform: Platformdescription
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.1, blue: 0.2),
                        Color(red: 0.05, green: 0.05, blue: 0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 平台 Logo
                        if let image = UIImage(named: platform.smallPic) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 100)
                                .padding(.top, 40)
                        }

                        // 平台描述
                        Text(platform.descripiton)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // 占位内容
                        VStack(spacing: 16) {
                            Text("直播内容列表")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)

                            // TODO: Add live room list here
                            ForEach(0..<5) { _ in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .frame(height: 100)
                                    .overlay {
                                        Text("加载中...")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.top, 30)
                    }
                }
            }
            .navigationTitle(platform.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension Platformdescription: Identifiable {
    public var id: String { title }
}

#Preview {
    PlatformView()
}
