//
//  PlatformView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/11.
//

import SwiftUI
import LiveParse

struct PlatformView: View {

    let column = Array(repeating: GridItem(.fixed(320), spacing: 70), count: 4)
    @FocusState var focusIndex: Int?
    @Environment(DanmuSettingModel.self) var danmuSettingModel
    @Environment(FavoriteModel.self) var favoriteModel
    @Environment(ContentViewModel.self) var contentViewModel
    @State var show = false
    @State var selectedIndex = 0
    let platformViewModel = PlatformViewModel()
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: column, alignment: .leading, spacing: 70) {
                    ForEach(platformViewModel.platformInfo.indices, id: \.self) { index in
                        Button {
                            selectedIndex = index
                            let model = platformViewModel.platformInfo[selectedIndex]
                            if model.liveType == .youtube {
                                contentViewModel.selection = 2
                            }else {
                                show = true
                            }
                            
                        } label: {
                            ZStack {
                                Image("platform-bg")
                                    .resizable()
                                    .frame(width: 320, height: 192)
                                Image(platformViewModel.platformInfo[index].bigPic)
                                    .resizable()
                                    .frame(width: 320, height: 192)
    //                                .opacity(focusIndex == index ? 0 : 1)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                ZStack {
                                    Image(platformViewModel.platformInfo[index].smallPic)
                                        .resizable()
                                        .frame(width: 320, height: 192)
                                    Text(platformViewModel.platformInfo[index].descripiton)
                                        .font(.system(size: 25))
                                        .multilineTextAlignment(.leading)
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
                            ListMainView(liveType: platformViewModel.platformInfo[selectedIndex].liveType)
                            .environment(favoriteModel)
                            .environment(danmuSettingModel)
                        })
                    }

                }
                .safeAreaPadding([.leading], 125)
                .padding(.top, 125)
            }
            .onAppear {
//                platformViewModel.platformInfo.removeAll()
                platformViewModel.getPlatformInfo()
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
