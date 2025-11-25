//
//  PlaySettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/9/21.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct GeneralSettingView: View {
    
    @Environment(AppState.self) var appViewModel
    @FocusState var focused: Bool
    @StateObject var settingStore = SettingStore()
    
    var body: some View {
        
        @Bindable var playerSettingModel = appViewModel.playerSettingsViewModel
        @Bindable var generalSettingModel = appViewModel.generalSettingsViewModel
        
        GeometryReader { geometry in
            HStack {
                VStack {
                    Spacer()
                    Image("icon")
                        .resizable()
                        .frame(width: 500, height: 500)
                        .padding(.top, 95)
                    Text("通用设置")
                        .font(.headline)
                        .padding(.top, 20)
                    Text(" ")
                        .font(.subheadline)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)
                VStack(spacing: 50) {
                    Spacer(minLength: 220)
                    HStack {
                        Text("播放设置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Toggle("直播结束后自动退出直播间", isOn: $playerSettingModel.openExitPlayerViewWhenLiveEnd)
                        .frame(height: 45)
                        .focused($focused)
                    if playerSettingModel.openExitPlayerViewWhenLiveEnd {
                        HStack {
                            Text("自动退出直播间时间：")
                            Menu(content: {
                                ForEach(PlayerSettingModel.timeArray.indices, id: \.self) { index in
                                    Button(PlayerSettingModel.timeArray[index]) {
                                        playerSettingModel.getTimeSecond(index: index)
                                    }
                                }
                            }, label: {
                                Text("\(PlayerSettingModel.timeArray[playerSettingModel.openExitPlayerViewWhenLiveEndSecondIndex])")
                                    .frame(width: 350, height: 45, alignment: .center)
                            })
                            
                        }
                        .frame(height: 45)
                    }
                    HStack {
                        Text("通用设置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Toggle("匹配系统帧率", isOn: $settingStore.syncSystemRate)
                        .frame(height: 45)
                    Toggle("禁用渐变背景", isOn: $generalSettingModel.generalDisableMaterialBackground)
                        .frame(height: 45)
                    Text("如果您的页面部分背景不正常（如页面背景透明）,请尝试打开这个选项。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("收藏设置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    HStack {
                        Text("收藏页面展示样式")
                        Spacer()
                        Menu(content: {
                            ForEach(AngelLiveFavoriteStyle.allCases, id: \.self) { index in
                                Button(AngelLiveFavoriteStyle.allCases[index.rawValue].description) {
                                    generalSettingModel.globalGeneralSettingFavoriteStyle = AngelLiveFavoriteStyle.allCases[index.rawValue].rawValue
                                }
                            }
                        }, label: {
                            Text(AngelLiveFavoriteStyle(rawValue: generalSettingModel.globalGeneralSettingFavoriteStyle)?.description ?? "普通视图")
                                .frame(width: 400, height: 45, alignment: .center)
                        })
                    }
                    .frame(height: 45)
                    AnyView(Color.clear)
                        .frame(height: 350)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                .padding(.trailing, 50)
            }
            
        }
    }
}

