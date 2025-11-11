//
//  PlatformView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore

struct PlatformView: View {
    @Environment(PlatformViewModel.self) private var platformViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 20) {
                    ForEach(platformViewModel.platformInfo, id: \.liveType) { platform in
                        PlatformCard(platform: platform)
                    }
                }
                .padding()
            }
            .navigationTitle("全部平台")
        }
    }
}

struct PlatformCard: View {
    let platform: Platformdescription

    var body: some View {
        VStack(spacing: 12) {
            Image(platform.bigPic)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 100)

            Text(platform.title)
                .font(.headline)

            Text(platform.descripiton)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppConstants.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    PlatformView()
        .environment(PlatformViewModel())
}
