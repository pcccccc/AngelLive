//
//  DanmuSettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/27.
//

import SwiftUI

struct DanmuSettingView: View {
    
    @Environment(AppState.self) var appViewModel
    
    var body: some View {
        
        @Bindable var danmuModel = appViewModel.danmuSettingsViewModel
        
        GeometryReader { geometry in
            HStack {
                VStack {
                    Spacer()
                    Image("icon")
                        .resizable()
                        .frame(width: 500, height: 500)
                        .padding(.top, 95)
                        .cornerRadius(50)
                    Text("弹幕设置")
                        .font(.headline)
                        .padding(.top, 20)
                    Text(" ")
                        .font(.subheadline)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)
                DanmuSettingMainView()
                    .environment(appViewModel)
                .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                .padding(.trailing, 50)
            }
            
        }
    }
}
