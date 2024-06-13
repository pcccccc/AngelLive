//
//  PlatformView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/11.
//

import SwiftUI
import LiveParse

struct PlatformView: View {
    @State var data = [LiveParsePlatformInfo]()
    let column = Array(repeating: GridItem(.fixed(320), spacing: 70), count: 4)
    @FocusState var focusIndex: Int?
    @Environment(DanmuSettingModel.self) var danmuSettingModel
    @Environment(FavoriteModel.self) var favoriteModel
    @State var show = false
    @State var selectedIndex = 0
    
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: column, alignment: .leading, spacing: 70) {
                    ForEach(data.indices, id: \.self) { index in
                        Button {
                            selectedIndex = index
                            show = true
                        } label: {
                            ZStack {
                                Image("platform-bg")
                                    .resizable()
                                    .frame(width: 320, height: 192)
                                Image("YouTube-big")
                                    .resizable()
                                    .frame(width: 320, height: 192)
    //                                .opacity(focusIndex == index ? 0 : 1)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                Image("platform-bg2")
                                    .resizable()
                                    .frame(width: 320, height: 192)
                                    .opacity(focusIndex == index ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                
                                ZStack {
                                    Image("YouTube-small")
                                        .resizable()
                                        .frame(width: 320, height: 192)
                                    Text("该平台需要自行解决代理问题，仅支持搜索观看")
                                        .font(.system(size: 25))
                                        .padding([.leading, .trailing], 15)
                                        .padding(.top, 50)
                                }
                                .background(.thinMaterial)
                                .opacity(focusIndex == index ? 1 : 0)
                                .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                            }
                        }
                        .buttonStyle(.card)
                        .background(.clear)
                        .focused($focusIndex, equals: index)
                        .transition(.moveAndOpacity)
                        .frame(width: 320, height: 192)
                        .fullScreenCover(isPresented: $show, content: {
                            ListMainView(liveType: data[selectedIndex].liveType)
                            .environment(favoriteModel)
                            .environment(danmuSettingModel)
                        
                        })
                    }

                }
                .safeAreaPadding([.leading], 125)
                .padding(.top, 125)
            }
            .onAppear {
                data.removeAll()
                let allPlatform = LiveParseTools.getAllSupportPlatform()
                for index in 0 ..< allPlatform.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(0.05 * Double(index))) {
                        withAnimation(.bouncy(duration: 0.25)) {
                            self.data.append(allPlatform[index])
                        }
                    }
                }
            }
            Text("敬请期待更多平台...")
                .foregroundStyle(.separator)
        }
    }
}

extension AnyTransition {
    static var moveAndOpacity: AnyTransition {
        AnyTransition.opacity
    }
}

#Preview {
    PlatformView()
}
