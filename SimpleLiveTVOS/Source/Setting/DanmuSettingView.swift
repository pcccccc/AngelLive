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
        VStack {
//            Text("弹幕设置")
//                .font(.title)
            HStack {
                VStack {
                    Spacer()
                    Image("icon")
                        .resizable()
                        .frame(width: 500, height: 500)
                    Text("弹幕设置")
                        .font(.headline)
                        .padding(.top, 20)
                    
                    Spacer()
                }
                .frame(maxHeight: .infinity)
                ScrollView(.vertical) {
                    Spacer(minLength: 120)
                    VStack(spacing: 50) {
                        Toggle("开启弹幕", isOn: $danmuSettingModel.showDanmu)
                            .frame(width: 500, height: 45)
                        Toggle("开启彩色弹幕", isOn: $danmuSettingModel.showColorDanmu)
                            .frame(width: 500, height: 45)
                        HStack {
                            Text("字体大小：")
                            Picker(selection: Binding(get: {
                                danmuSettingModel.danmuFontSizeIndex
                            }, set: { value in
                                danmuSettingModel.danmuFontSizeIndex = value
                                switch danmuSettingModel.danmuFontSizeIndex {
                                    case 0:
                                        danmuSettingModel.danmuFontSize = 30
                                    case 1:
                                        danmuSettingModel.danmuFontSize = 50
                                    case 2:
                                        danmuSettingModel.danmuFontSize = 65
                                    default:
                                        danmuSettingModel.danmuFontSize = 50
                                }
                            })) {
                                ForEach(danmuSettingModel.danmuFontSizeArray.indices, id: \.self) { index in
                                    // 需要有一个变量text。不然会自动帮忙加很多0
                                    let text = danmuSettingModel.danmuFontSizeArray[index]
                                    Text(text)
                                }
                            } label: {
                                Text("字体大小")
                            }
                        }
                        .frame(width: 500, height: 45)
                        HStack {
                            Text("    透明度：")
                            TextField("透明度：(0.1-1.0)", text: Binding(
                                get: {
                                    "\(danmuSettingModel.danmuAlpha)"
                                }, set: {
                                    danmuSettingModel.danmuAlpha = Double($0) ?? 1.0
                                }
                            ))
                                .keyboardType(.decimalPad)
                                .submitLabel(.done)
                        }
                        .frame(width: 500, height: 45)
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
                        .frame(width: 500, height: 45)
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
                                    .frame(width: 210, height: 45, alignment: .center)
                            })
                            
                        }
                        .frame(width: 500, height: 45)
                    }.padding()
                }
                .frame(width: 500)
                .padding(.leading, 50)
                .onAppear {
                    
                }
            }
        }
    }
}

#Preview {
    DanmuSettingView()
}
