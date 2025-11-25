//
//  DanmuSettingMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/8/24.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

struct DanmuSettingMainView: View {
    
    @Environment(AppState.self) var appViewModel
    @FocusState var showDanmuView: Bool
    
    var body: some View {
        
        @Bindable var danmuModel = appViewModel.danmuSettingsViewModel
        
        VStack(spacing: 50) {
            Spacer()
            Toggle("开启弹幕", isOn: $danmuModel.showDanmu)
                .frame(height: 45)
                .focused($showDanmuView)
            Toggle("开启彩色弹幕", isOn: $danmuModel.showColorDanmu)
                .frame(height: 45)
            HStack {
                Text("字体大小：")
                    .multilineTextAlignment(.leading)
                Spacer()
                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize -= 5
                } label: {
                    Text("-5")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)
                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize -= 1
                } label: {
                    Text("-1")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)
                
                Text("\(appViewModel.danmuSettingsViewModel.danmuFontSize)")
                    .font(.system(size: CGFloat(appViewModel.danmuSettingsViewModel.danmuFontSize)))
                
                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize += 1
                } label: {
                    Text("+1")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)
                
                Button {
                    appViewModel.danmuSettingsViewModel.danmuFontSize += 5
                } label: {
                    Text("+5")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                
                .clipShape(.circle)
                .frame(width: 40, height:40)
                Spacer()
            }
            .frame(height: 45)
            HStack {
                Text("这是一条测试弹幕")
                    .font(.system(size: CGFloat(appViewModel.danmuSettingsViewModel.danmuFontSize)))
            }
            .frame(height: 45)
            HStack {
                Text("    透明度：")
                TextField("透明度：(0.1-1.0)", text: $danmuModel.danmuAlphaString)
                    .keyboardType(.decimalPad)
                    .submitLabel(.done)
                    .onChange(of: appViewModel.danmuSettingsViewModel.danmuAlphaString) { oldValue, newValue in
                        if Double(newValue) != nil && Double(newValue) ?? 0 > 0.09 && Double(newValue) ?? 0 < 1.01  {
                            appViewModel.danmuSettingsViewModel.danmuAlpha = Double(newValue)!
                        }
                    }
                    .onAppear {
                        appViewModel.danmuSettingsViewModel.danmuAlphaString = "\(appViewModel.danmuSettingsViewModel.danmuAlpha)"
                    }
                
            }
            .frame(height: 45)
            HStack {
                Text("弹幕速度：")
                Picker(selection: Binding(get: {
                    appViewModel.danmuSettingsViewModel.danmuSpeedIndex
                }, set: { value in
                    appViewModel.danmuSettingsViewModel.danmuSpeedIndex = value
                    switch appViewModel.danmuSettingsViewModel.danmuSpeedIndex {
                        case 0:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.3
                        case 1:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.5
                        case 2:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.7
                        default:
                            appViewModel.danmuSettingsViewModel.danmuSpeed = 0.5
                    }
                })) {
                    ForEach(DanmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                        // 需要有一个变量text。不然会自动帮忙加很多0
                        let text = DanmuSettingModel.danmuSpeedArray[index]
                        Text(text)
                    }
                } label: {
                    Text("弹幕速度：")
                }
            }
            .frame(height: 45)
            HStack {
                Text("显示区域：")
                Menu(content: {
                    ForEach(DanmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                        Button(DanmuSettingModel.danmuAreaArray[index]) {
                            appViewModel.danmuSettingsViewModel.danmuAreaIndex = index
                        }
                    }
                }, label: {
                    Text("\(DanmuSettingModel.danmuAreaArray[appViewModel.danmuSettingsViewModel.danmuAreaIndex])")
                        .frame(width: 535, height: 45, alignment: .center)
                })
                
            }
            .frame(height: 45)
            Spacer()
        }
    }
}

#Preview {
    DanmuSettingMainView()
}
