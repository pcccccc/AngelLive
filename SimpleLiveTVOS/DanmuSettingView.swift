//
//  DanmuSettingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/27.
//

import SwiftUI

struct DanmuSettingView: View {

    @State var showDanmu = SettingStore.shared.showDanmu
    @State var showColorDanmu = SettingStore.shared.showColorDanmu
    @State var danmuFontSize = "\(SettingStore.shared.danmuFontSize)"
    @State var danmuSpeed = "\(SettingStore.shared.danmuSpeed)"
    @State var danmuAlpha = "\(SettingStore.shared.danmuAlpha)"
    @State var danmuTopMargin = "\(SettingStore.shared.danmuTopMargin)"
    @State var danmuBottonMargin = "\(SettingStore.shared.danmuBottomMargin)"
    
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
                        Toggle("开启弹幕", isOn: $showDanmu)
                            .onChange(of: showDanmu, perform: { newValue in
                                SettingStore.shared.showDanmu = newValue
                        })
                            .frame(width: 500, height: 45)
                        Toggle("开启彩色弹幕", isOn: $showColorDanmu)
                            .onChange(of: showColorDanmu, perform: { newValue in
                                SettingStore.shared.showColorDanmu = newValue
                        })
                            .frame(width: 500, height: 45)
                        HStack {
                            Text("字体大小：")
                            TextField("字体大小：(0-100)", text: $danmuFontSize)
                                .keyboardType(.numberPad)
                                .submitLabel(.done)
                                .onChange(of: danmuFontSize, perform: { newValue in
                                    SettingStore.shared.danmuFontSize = Int(newValue) ?? 50
                                })
                        }
                        .frame(width: 500, height: 45)
                        HStack {
                            Text("    透明度：")
                            TextField("透明度：(0.1-1.0)", text: $danmuAlpha)
                                .keyboardType(.decimalPad)
                                .submitLabel(.done)
                                .onChange(of: danmuAlpha, perform: { newValue in
                                    SettingStore.shared.danmuAlpha = Float(newValue) ?? 1.0
                                })
                        }
                        .frame(width: 500, height: 45)
                        HStack {
                            Text("弹幕速度：")
                            TextField("弹幕速度：(0.1-1.0)", text: $danmuSpeed)
                                .keyboardType(.decimalPad)
                                .submitLabel(.done)
                                .onChange(of: danmuSpeed, perform: { newValue in
                                    SettingStore.shared.danmuSpeed = Float(newValue) ?? 0.5
                                })
                        }
                        .frame(width: 500, height: 45)
                        HStack {
                            Text("顶部边距：")
                            TextField("顶部边距：", text: $danmuTopMargin)
                                .keyboardType(.numberPad)
                            
                                .onChange(of: danmuTopMargin, perform: { newValue in
                                    SettingStore.shared.danmuTopMargin = Float(newValue) ?? 0
                                })
                        }
                        .frame(width: 500, height: 45)
                        HStack {
                            Text("底部边距：")
                            TextField("底部边距：", text: $danmuBottonMargin)
                                .keyboardType(.numberPad)
                                .submitLabel(.done)
                                .onChange(of: danmuBottonMargin, perform: { newValue in
                                    SettingStore.shared.danmuBottomMargin = Float(newValue) ?? 0
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
