////
////  BiliBiliMainView.swift
////  SimpleLiveTVOS
////
////  Created by pangchong on 2023/9/14.
////

import SwiftUI
import Kingfisher
import SimpleToast
import LiveParse
import GameController
import Shimmer

enum FocusableField: Hashable {
    case leftMenu(Int, Int)
    case mainContent(Int)
    case leftFavorite(Int, Int)
}

struct ListMainView: View {
    
    @Environment(\.scenePhase) var scenePhase
    @State var needFullScreenLoading: Bool = false
    private static let topId = "topIdHere"
    
    var liveType: LiveType
    var liveViewModel: LiveViewModel
    @FocusState var focusState: FocusableField?
    var appViewModel: SimpleLiveViewModel
    
    init(liveType: LiveType, appViewModel: SimpleLiveViewModel) {
        self.liveType = liveType
        self.appViewModel = appViewModel
        self.liveViewModel = LiveViewModel(roomListType: .live, liveType: liveType, appViewModel: appViewModel)
    }
    
    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        
        ZStack {
            ScrollViewReader { reader in
                ScrollView {
                    ZStack {
                        Text(liveModel.livePlatformName)
                            .font(.largeTitle)
                    }
                    .id(Self.topId)
                    LazyVGrid(columns: [GridItem(.fixed(380), spacing: 50), GridItem(.fixed(380), spacing: 50), GridItem(.fixed(380), spacing: 50), GridItem(.fixed(380), spacing: 50)], spacing: 50) {
                        ForEach(liveViewModel.roomList.indices, id: \.self) { index in
                            LiveCardView(index: index)
                                .environment(liveViewModel)
                                .onMoveCommand(perform: { direction in
                                    switch direction {
                                    case .left:
                                        if index % 4 == 0 {
                                            liveViewModel.showOverlay = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
                                                focusState = .leftMenu(0, 0)
                                            })
                                        }
                                    default:
                                        break
                                    }
                                })
                                .onPlayPauseCommand(perform: {
                                    liveViewModel.roomPage = 1
                                    liveViewModel.getRoomList(index: liveViewModel.selectedSubListIndex)
                                    reader.scrollTo(Self.topId)
                                })
                                .frame(width: 370, height: 280)
                        }
                        if liveViewModel.isLoading {
                            LoadingView()
                                .frame(width: 370, height: 280)
                                .cornerRadius(5)
                                .shimmering(active: true)
                                .redacted(reason: .placeholder)
                        }
                    }
                }
//                .scrollTransition { content, phase in
//                    content
//                        .opacity(phase.isIdentity ? 1 : 1)
//                        .scaleEffect(phase.isIdentity ? 1 : 0.75)
//                        .blur(radius: phase.isIdentity ? 0 : 10)
//                }
            }.overlay {
                if liveModel.roomList.count > 0 {
                    ZStack {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top) {
                                ZStack {
                                    if appViewModel.generalSettingModel.generalDisableMaterialBackground {
                                        LeftMenu(focusState: _focusState)
                                            .environment(liveViewModel)
                                            .opacity(liveViewModel.showOverlay ? 1 : 0)
                                            .background(
                                                Color("sl-background", bundle: nil)
                                                    .opacity(liveViewModel.showOverlay ? 1 : 0)
                                            )
                                            .animation(.easeInOut(duration: 0.25), value: liveViewModel.showOverlay)
                                            .edgesIgnoringSafeArea(.all)
                                            .frame(width: 320, height: 1080)
                                            .cornerRadius(liveViewModel.leftMenuCornerRadius)
                                    }else {
                                        LeftMenu(focusState: _focusState)
                                            .environment(liveViewModel)
                                            .opacity(liveViewModel.showOverlay ? 1 : 0)
                                            .animation(.easeInOut(duration: 0.25), value: liveViewModel.showOverlay)
                                            .edgesIgnoringSafeArea(.all)
                                            .frame(width: 320, height: 1080)
                                            .cornerRadius(liveViewModel.leftMenuCornerRadius)
                                    }
                                    VStack(alignment: .leading) {
                                        HStack {
                                            IndicatorMenuView()
                                                .environment(liveViewModel)
                                        }
                                        .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftHeight)

                                        Button {
                                            //                                            print(1)
                                        } label: {
                                            Text("")
                                                .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftMenuMaxHeight - liveViewModel.leftHeight)
                                        }
                                        .background(Color.clear)
                                        .opacity(0)
                                        .buttonStyle(.plain)
                                        .focusable(liveModel.endFirstLoading) { focus in
                                            if focus {
                                                liveViewModel.showOverlay = true
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
                                                    focusState = .leftMenu(0, 0)
                                                })
                                            }
                                        }

                                       
//                                        .onChange(of: focusState) { oldValue, newValue in
//                                            switch newValue {
//                                                case .leftMenu(let mainIndex, let cateIndex):
//                                                    liveViewModel.showOverlay = true
//                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
//                                                        focusState = .leftMenu(0, 0)
//                                                    })
//                                                default:
//                                                    break
//                                            }
//                                            
//                                        }

                                        
                                    }
                                    
                                    .frame(width: liveViewModel.showOverlay == true ? 150: 300, height: liveViewModel.showOverlay == true ? liveViewModel.leftMenuMinHeight:  liveViewModel.leftMenuMaxHeight)
                                }
                                .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftMenuMaxHeight)
                                
                                Spacer()
                            }
                            .frame(height: 1080)
                        }
                        .edgesIgnoringSafeArea(.all)
                        .frame(width: 1920, height: 1080)
                        .background(liveModel.showOverlay ? .black.opacity(0.4) : .clear)
                    }
                    .onMoveCommand(perform: { direction in
                        if direction == .left {
                            //                        liveViewModel.showOverlay = true
                        }else if direction == .right {
                            //                        liveViewModel.showOverlay = false
                            focusState = .mainContent(liveViewModel.selectedRoomListIndex)
                        }
                    })
                    .onExitCommand {
                        switch focusState {
                        case .leftMenu(_, _):
                            //                            liveViewModel.showOverlay = false
                            focusState = .mainContent(liveViewModel.selectedRoomListIndex)
                        case .leftFavorite(_, _):
                            //                            liveViewModel.showOverlay = false
                            focusState = .mainContent(liveViewModel.selectedRoomListIndex)
                        case .mainContent(_):
                            break
                        case .none:
                            break
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 50)
                    .padding(.leading, 10)
                }
                
            }
            
            
        }
        .background(.thinMaterial)
        .onChange(of: focusState, { oldValue, newValue in
            switch newValue {
            case .leftMenu(_, _):
                liveViewModel.showOverlay = true
            case .leftFavorite(_, _):
                liveViewModel.showOverlay = true
            default:
                liveViewModel.showOverlay = false
            }
        })
        .simpleToast(isPresented: $liveModel.showToast, options: liveModel.toastOptions) {
            VStack(alignment: .leading) {
                Label("提示", systemImage: liveModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                    .font(.headline.bold())
                Text(liveModel.toastTitle)
            }
            .padding()
            .background(.black.opacity(0.6))
            .foregroundColor(Color.white)
            .cornerRadius(10)
        }
        .onPlayPauseCommand(perform: {
            liveViewModel.getRoomList(index: 1)
        })
        .onChange(of: scenePhase) { oldValue, newValue in
            switch newValue {
                case .active:
                    liveViewModel.showToast(true, title: "程序返回前台，正在为您刷新列表", hideAfter: 3)
                    liveViewModel.roomPage = 1
                case .background:
                    print("background。。。。")
                case .inactive:
                    print("inactive。。。。")
                @unknown default:
                    break
            }
        }
    }
}

