//
//  DetailPlayerView.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct DetailPlayerView: View {
    @Environment(RoomInfoViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 背景色
            AppConstants.Colors.primaryBackground
                .ignoresSafeArea()

            VStack {
                Text("播放器详情页")
                    .font(.title)
                    .foregroundStyle(AppConstants.Colors.primaryText)

                Text(viewModel.currentRoom.roomTitle)
                    .font(.headline)
                    .foregroundStyle(AppConstants.Colors.secondaryText)

                Button("关闭") {
                    dismiss()
                }
                .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
