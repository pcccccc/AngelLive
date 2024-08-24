//
//  DanmuSettingMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/8/24.
//

import SwiftUI

struct DanmuSettingMainView: View {
    
    @Environment(SimpleLiveViewModel.self) var appViewModel
    @FocusState var showDanmuView: Bool
    
    var body: some View {
        
        @Bindable var danmuModel = appViewModel.danmuSettingModel
        
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
                    appViewModel.danmuSettingModel.danmuFontSize -= 5
                } label: {
                    Text("-5")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)
                Button {
                    appViewModel.danmuSettingModel.danmuFontSize -= 1
                } label: {
                    Text("-1")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)
                
                Text("\(appViewModel.danmuSettingModel.danmuFontSize)")
                    .font(.system(size: CGFloat(appViewModel.danmuSettingModel.danmuFontSize)))
                
                Button {
                    appViewModel.danmuSettingModel.danmuFontSize += 1
                } label: {
                    Text("+1")
                        .font(.subheadline)
                        .frame(width: 40, height:40)
                }
                .clipShape(.circle)
                .frame(width: 40, height:40)
                
                Button {
                    appViewModel.danmuSettingModel.danmuFontSize += 5
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
                    .font(.system(size: CGFloat(appViewModel.danmuSettingModel.danmuFontSize)))
            }
            .frame(height: 45)
            HStack {
                Text("    透明度：")
                TextField("透明度：(0.1-1.0)", text: $danmuModel.danmuAlphaString)
                    .keyboardType(.decimalPad)
                    .submitLabel(.done)
                    .onChange(of: appViewModel.danmuSettingModel.danmuAlphaString) { oldValue, newValue in
                        if Double(newValue) != nil && Double(newValue) ?? 0 > 0.09 && Double(newValue) ?? 0 < 1.01  {
                            appViewModel.danmuSettingModel.danmuAlpha = Double(newValue)!
                        }
                    }
                    .onAppear {
                        appViewModel.danmuSettingModel.danmuAlphaString = "\(appViewModel.danmuSettingModel.danmuAlpha)"
                    }
                
            }
            .frame(height: 45)
            HStack {
                Text("弹幕速度：")
                Picker(selection: Binding(get: {
                    appViewModel.danmuSettingModel.danmuSpeedIndex
                }, set: { value in
                    appViewModel.danmuSettingModel.danmuSpeedIndex = value
                    switch appViewModel.danmuSettingModel.danmuSpeedIndex {
                        case 0:
                            appViewModel.danmuSettingModel.danmuSpeed = 0.3
                        case 1:
                            appViewModel.danmuSettingModel.danmuSpeed = 0.5
                        case 2:
                            appViewModel.danmuSettingModel.danmuSpeed = 0.7
                        default:
                            appViewModel.danmuSettingModel.danmuSpeed = 0.5
                    }
                })) {
                    ForEach(appViewModel.danmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                        // 需要有一个变量text。不然会自动帮忙加很多0
                        let text = appViewModel.danmuSettingModel.danmuSpeedArray[index]
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
                    ForEach(appViewModel.danmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                        Button(appViewModel.danmuSettingModel.danmuAreaArray[index]) {
                            appViewModel.danmuSettingModel.danmuAreaIndex = index
                        }
                    }
                }, label: {
                    Text("\(appViewModel.danmuSettingModel.danmuAreaArray[appViewModel.danmuSettingModel.danmuAreaIndex])")
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
