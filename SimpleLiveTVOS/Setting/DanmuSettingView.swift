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
                            TextField("字体大小：(0-100)", text: Binding(
                                get: { 
                                    "\(danmuSettingModel.danmuFontSize)"
                                }, set: {
                                    danmuSettingModel.danmuFontSize = Int($0) ?? 50
                                }
                            ))
                                .keyboardType(.decimalPad)
                                .submitLabel(.done)
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
                            TextField("弹幕速度：(0.1-1.0)", text: Binding(
                                get: {
                                    "\(danmuSettingModel.danmuSpeed)"
                                }, set: {
                                    danmuSettingModel.danmuSpeed = Double($0) ?? 0.5
                                }
                            ))
                                .keyboardType(.decimalPad)
                                .submitLabel(.done)
                        }
                        .frame(width: 500, height: 45)
                        HStack {
                            Text("显示区域：")
                            Menu(content: {
                                ForEach(danmuSettingModel.danmuArea.indices, id: \.self) { index in
                                    Button(danmuSettingModel.danmuArea[index]) {
                                        danmuSettingModel.danmuAreaIndex = index
                                    }
                                }
                            }, label: {
                                Text("\(danmuSettingModel.danmuArea[danmuSettingModel.danmuAreaIndex])")
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
