//
//  FavoriteMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/11.
//

import SwiftUI
import Kingfisher
import SimpleToast
import LiveParse
import Shimmer
import TipKit

struct FavoriteMainView: View {
    
    @FocusState var focusState: Int?
    @Environment(LiveViewModel.self) var liveViewModel
    @Environment(SimpleLiveViewModel.self) var appViewModel
    
    var body: some View {
        
        @Bindable var appModel = appViewModel
        
        VStack {
            if appViewModel.favoriteModel.cloudKitReady {
                if liveViewModel.roomList.isEmpty && liveViewModel.isLoading == false {
                    Text("暂无喜欢的主播哦，请先去添加吧～")
                        .font(.title3)
                }else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60), GridItem(.fixed(370), spacing: 60)], spacing: 60) {
                            ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                                LiveCardView(index: index)
                                    .environment(liveViewModel)
                                    .environment(appViewModel)
                                    .frame(width: 370, height: 240)
                            }
                            if liveViewModel.isLoading {
                                LoadingView()
                                    .frame(width: 370, height: 275)
                                    .cornerRadius(5)
                                    .shimmering(active: true)
                                    .redacted(reason: .placeholder)
                            }
                        }
                        .safeAreaPadding(.top, 15)
                    }
                }
            }else {
                Text(appViewModel.favoriteModel.cloudKitStateString)
                    .font(.title3)
            }
        }
//        .overlay {
//            VStack(alignment: .leading) {
//                Spacer()
//                HStack {
//                    VStack(alignment: .leading) {
//                        VStack {
//                            Text("收藏方式")
//                            Button {
//                                
//                            } label: {
//                                Text("iCloud")
//                                    .frame(alignment: .leading)
//                            }
//                            Button {
//                                
//                            } label: {
//                                Text("SimpleLiveCloud")
//                                    .frame(alignment: .leading)
//                                    
//                            }
//                            .frame(alignment: .leading)
//                        }
//                        Button {
//                            
//                        } label: {
//                            Image(systemName: "chevron.backward.circle.fill")
//                                .frame(width: 30, height: 30)
//                            Text("菜单")
//                                .padding(.leading, -30)
//                        }
//                    }
//                    .background(.red)
//                    Spacer()
//                }
//                .padding([.leading, .bottom], 20)
//            }
//            .frame(width: 1920, height: 1080)
//            .edgesIgnoringSafeArea(.all)
//            .background(.green)
//        }
        .onPlayPauseCommand(perform: {
            liveViewModel.getRoomList(index: 1)
        })
    }
}
