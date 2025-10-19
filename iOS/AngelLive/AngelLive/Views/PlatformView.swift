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
        VStack(spacing: AppConstants.Spacing.md) {
            if let image = UIImage(named: platform.smallPic) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
            } else {
                Image(systemName: "play.tv")
                    .font(.system(size: 50))
                    .foregroundStyle(AppConstants.Colors.primaryText)
            }

            Text(platform.title)
                .font(.title3.bold())
                .foregroundStyle(AppConstants.Colors.primaryText)

            Text(platform.descripiton)
                .font(.caption)
                .foregroundStyle(AppConstants.Colors.tertiaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, AppConstants.Spacing.sm)
        }
        .padding(AppConstants.Spacing.lg)
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.xl)
                .fill(AppConstants.Colors.materialBackground)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3), value: isPressed)
        .shadow(
            color: AppConstants.Shadow.lg.color,
            radius: AppConstants.Shadow.lg.radius,
            x: AppConstants.Shadow.lg.x,
            y: AppConstants.Shadow.lg.y
        )
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
                        .foregroundStyle(AppConstants.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // 占位内容
                    VStack(spacing: AppConstants.Spacing.lg) {
                        Text("直播内容列表")
                            .font(.headline)
                            .foregroundStyle(AppConstants.Colors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        // TODO: Add live room list here
                        ForEach(0..<5) { _ in
                            RoundedRectangle(cornerRadius: AppConstants.CornerRadius.md)
                                .fill(AppConstants.Colors.materialBackground)
                                .frame(height: 100)
                                .overlay {
                                    Text("加载中...")
                                        .foregroundStyle(AppConstants.Colors.secondaryText)
                                }
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top, 30)
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
