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
    let platformViewModel = PlatformViewModel()
    @FocusState var focusIndex: Int?
    @Environment(SimpleLiveViewModel.self) var appViewModel
    @State var show = false
    @State var selectedIndex = 0
    
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: column, alignment: .leading, spacing: 70) {
                    ForEach(platformViewModel.platformInfo.indices, id: \.self) { index in
                        Button {
                            selectedIndex = index
                            let model = platformViewModel.platformInfo[selectedIndex]
                            if model.liveType == .youtube {
                                appViewModel.selection = 2
                                appViewModel.searchModel.searchTypeIndex = 2
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
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                    .blur(radius: focusIndex == index ? 10 : 0)
                                
                                if #available(tvOS 18.0, *) {
                                    ZStack {
                                        Image(platformViewModel.platformInfo[index].smallPic)
                                            .resizable()
                                            .frame(width: 320, height: 192)
                                        Text(platformViewModel.platformInfo[index].descripiton)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                            .padding([.leading, .trailing], 15)
                                            .padding(.top, 50)
                                            
                                    }
                                    .background(Color("sl-background", bundle: nil))
                                    .opacity(focusIndex == index ? 0.9 : 0)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                }else {
                                    ZStack {
                                        Image(platformViewModel.platformInfo[index].smallPic)
                                            .resizable()
                                            .frame(width: 320, height: 192)
                                        Text(platformViewModel.platformInfo[index].descripiton)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                            .padding([.leading, .trailing], 15)
                                            .padding(.top, 50)
                                            
                                    }
                                    .background(.thinMaterial)
                                    .opacity(focusIndex == index ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                }
                                
                            }
                        }
                        .buttonStyle(.card)
                        .background(.clear)
                        .focused($focusIndex, equals: index)
                        .transition(.moveAndOpacity)
                        .animation(.easeInOut(duration: 0.25) ,value: true)
                        .frame(width: 320, height: 192)
                        .fullScreenCover(isPresented: $show, content: {
                            if #available(tvOS 18.0, *) {
                                ListMainView(liveType: platformViewModel.platformInfo[selectedIndex].liveType, appViewModel: appViewModel)
                                    .background(
                                        Color("sl-background", bundle: nil)
                                            .blur(radius: 10)
                                            .opacity(0.6)
                                    )
                                
                            }else {
                                ListMainView(liveType: platformViewModel.platformInfo[selectedIndex].liveType, appViewModel: appViewModel)
                            }
                        })
                    }

                }
                .safeAreaPadding([.leading], 125)
                .padding(.top, 125)
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
