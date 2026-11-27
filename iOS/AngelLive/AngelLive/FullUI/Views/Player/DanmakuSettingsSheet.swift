//
//  DanmakuSettingsSheet.swift
//  AngelLive
//
//  Created by pangchong on 11/2/25.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

/// 播放器弹幕设置面板（BottomSheet 样式）
struct DanmakuSettingsSheet: View {
    @Binding var isPresented: Bool
    @Environment(RoomInfoViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            DanmakuSettingsList(danmuModel: viewModel.danmuSettings)
                .playerSheetNavigation(Text("弹幕设置")) { isPresented = false }
        }
    }
}

#Preview {
    DanmakuSettingsSheet(isPresented: .constant(true))
}
