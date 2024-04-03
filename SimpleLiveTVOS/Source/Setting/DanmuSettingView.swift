//
//  DanmuSettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/27.
//

import SwiftUI

struct DanmuSettingView: View {
    
    @EnvironmentObject var danmuSettingModel: DanmuSettingStore

    var body: some View {
        GeometryReader { geometry in
            HStack {
                VStack {
                    Spacer()
                    Image("icon")
                        .resizable()
                        .frame(width: 500, height: 500)
                        .padding(.top, 95)
                    Text("弹幕设置")
                        .font(.headline)
                        .padding(.top, 20)
                    Text(" ")
                        .font(.subheadline)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)
                VStack(spacing: 50) {
                    Spacer()
                    Toggle("开启弹幕", isOn: $danmuSettingModel.showDanmu)
                        .frame(height: 45)
                    Toggle("开启彩色弹幕", isOn: $danmuSettingModel.showColorDanmu)
                        .frame(height: 45)
                    HStack {
                        Text("字体大小：")
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Button {
                            danmuSettingModel.danmuFontSize -= 5
                        } label: {
                            Text("-5")
                                .font(.subheadline)
                                .frame(width: 40, height:40)
                        }
                        .clipShape(.circle)
                        .frame(width: 40, height:40)
                        Button {
                            danmuSettingModel.danmuFontSize -= 1
                        } label: {
                            Text("-1")
                                .font(.subheadline)
                                .frame(width: 40, height:40)
                        }
                        .clipShape(.circle)
                        .frame(width: 40, height:40)
                        
                        Text("\(danmuSettingModel.danmuFontSize)")
                            .font(.system(size: CGFloat(danmuSettingModel.danmuFontSize)))
                        
                        Button {
                            danmuSettingModel.danmuFontSize += 1
                        } label: {
                            Text("+1")
                                .font(.subheadline)
                                .frame(width: 40, height:40)
                        }
                        .clipShape(.circle)
                        .frame(width: 40, height:40)
                        
                        Button {
                            danmuSettingModel.danmuFontSize += 5
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
                            .font(.system(size: CGFloat(danmuSettingModel.danmuFontSize)))
                    }
                    .frame(height: 45)
                    HStack {
                        Text("    透明度：")
                        TextField("透明度：(0.1-1.0)", text: $danmuSettingModel.danmuAlphaString)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onChange(of: danmuSettingModel.danmuAlphaString) { oldValue, newValue in
                                if Double(newValue) != nil && Double(newValue) ?? 0 > 0.09 && Double(newValue) ?? 0 < 1.01  {
                                    danmuSettingModel.danmuAlpha = Double(newValue)!
                                }
                            }
                            .onAppear {
                                danmuSettingModel.danmuAlphaString = "\(danmuSettingModel.danmuAlpha)"
                            }
                        
                    }
                    .frame(height: 45)
                    HStack {
                        Text("弹幕速度：")
                        Picker(selection: Binding(get: {
                            danmuSettingModel.danmuSpeedIndex
                        }, set: { value in
                            danmuSettingModel.danmuSpeedIndex = value
                            switch danmuSettingModel.danmuSpeedIndex {
                                case 0:
                                    danmuSettingModel.danmuSpeed = 0.3
                                case 1:
                                    danmuSettingModel.danmuSpeed = 0.5
                                case 2:
                                    danmuSettingModel.danmuSpeed = 0.7
                                default:
                                    danmuSettingModel.danmuSpeed = 0.5
                            }
                        })) {
                            ForEach(danmuSettingModel.danmuSpeedArray.indices, id: \.self) { index in
                                // 需要有一个变量text。不然会自动帮忙加很多0
                                let text = danmuSettingModel.danmuSpeedArray[index]
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
                            ForEach(danmuSettingModel.danmuAreaArray.indices, id: \.self) { index in
                                Button(danmuSettingModel.danmuAreaArray[index]) {
                                    danmuSettingModel.danmuAreaIndex = index
                                }
                            }
                        }, label: {
                            Text("\(danmuSettingModel.danmuAreaArray[danmuSettingModel.danmuAreaIndex])")
                                .frame(width: 535, height: 45, alignment: .center)
                        })
                        
                    }
                    .frame(height: 45)
                    Spacer()
                }
                .frame(width: geometry.size.width / 2 - 50, height: geometry.size.height)
                .padding(.trailing, 50)
            }
        }
    }
}

#Preview {
    DanmuSettingView()
}
