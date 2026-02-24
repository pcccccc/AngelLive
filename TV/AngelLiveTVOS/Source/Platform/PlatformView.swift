//
//  PlatformView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/11.
//

import SwiftUI
import AngelLiveDependencies

struct PlatformView: View {

    let column = Array(repeating: GridItem(.fixed(380), spacing: 50), count: 4)
    let platformViewModel = PlatformViewModel()
    @FocusState var focusIndex: Int?
    @Environment(AppState.self) var appViewModel
    @State var show = false
    @State var selectedIndex = 0


    var body: some View {
        VStack {
            ScrollView {
                LazyVGrid(columns: column, alignment: .center, spacing: 50) {
                    ForEach(platformViewModel.platformInfo.indices, id: \.self) { index in
                        Button {
                            selectedIndex = index
                            show = true
                        } label: {
                            ZStack {
                                Image("platform-bg")
                                    .resizable()
                                    .frame(width: 370, height: 222)
                                Image(platformViewModel.platformInfo[index].bigPic)
                                    .resizable()
                                    .frame(width: 370, height: 222)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                    .blur(radius: focusIndex == index ? 10 : 0)

                                if appViewModel.generalSettingsViewModel.generalDisableMaterialBackground {
                                    ZStack {
                                        Image(platformViewModel.platformInfo[index].smallPic)
                                            .resizable()
                                            .frame(width: 370, height: 222)
                                        Text(platformViewModel.platformInfo[index].descripiton)
                                            .font(.body)
                                            .multilineTextAlignment(.leading)
                                            .padding([.leading, .trailing], 15)
                                            .padding(.top, 50)

                                    }
                                    .background(Color("sl-background", bundle: nil))
                                    .opacity(focusIndex == index ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.25), value: focusIndex == index)
                                }else {
                                    ZStack {
                                        Image(platformViewModel.platformInfo[index].smallPic)
                                            .resizable()
                                            .frame(width: 370, height: 222)
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
                        .frame(width: 380, height: 230)
                    }

                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 125)
            }
            .fullScreenCover(isPresented: $show, content: {
                if appViewModel.generalSettingsViewModel.generalDisableMaterialBackground {
                    ListMainView(liveType: platformViewModel.platformInfo[selectedIndex].liveType, appViewModel: appViewModel)
                        .background(
                            Color("sl-background", bundle: nil)
                        )
                        .safeAreaPadding(.all)
                        .id(platformViewModel.platformInfo[selectedIndex].liveType)

                }else {
                    ListMainView(liveType: platformViewModel.platformInfo[selectedIndex].liveType, appViewModel: appViewModel)
                        .id(platformViewModel.platformInfo[selectedIndex].liveType)
                }
            })
            
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
