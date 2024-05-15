//
//  BiliBiliMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/9/14.
//

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
    
    @State var needFullScreenLoading: Bool = false
    private static let topId = "topIdHere"
    
    var liveType: LiveType
    var liveViewModel: LiveViewModel
    @FocusState var focusState: FocusableField?

    @Environment(DanmuSettingModel.self) var danmuSettingModel
    @Environment(FavoriteModel.self) var favoriteModel
    
    init(liveType: LiveType) {
        self.liveType = liveType
        self.liveViewModel = LiveViewModel(roomListType: .live, liveType: liveType)
    }
    
    var body: some View {
        
        @Bindable var liveModel = liveViewModel
        
        ZStack {
            ScrollViewReader { reader in
                ScrollView {
                    ZStack {
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
                                        print("default")
                                    }
                                })
                                .onPlayPauseCommand(perform: {
                                    liveViewModel.roomPage = 1
                                    liveViewModel.getRoomList(index: liveViewModel.selectedSubListIndex)
                                    reader.scrollTo(Self.topId)
                                })
                                .frame(width: 370, height: 280)
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
                ZStack {
                    VStack(alignment: .leading, spacing: 50) {
                        HStack(alignment: .top) {
                            ZStack {
                                VStack(alignment: .leading) {
                                    HStack {
                                        LeftMenu(focusState: _focusState)
                                            .environment(liveViewModel)
                                            .animation(.easeInOut(duration: 0.25), value: liveViewModel.showOverlay)
                                            .edgesIgnoringSafeArea(.all)
                                            .frame(width: liveViewModel.leftWidth, height: liveViewModel.leftHeight)
                                            .cornerRadius(liveViewModel.leftMenuCornerRadius)
                                        
                                        Spacer(minLength: 0)
                                    }
                                    .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftHeight)
                                    Button {
                                        
                                    } label: {
                                        Text("")
                                            .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftMenuMaxHeight - liveViewModel.leftHeight)
                                    }
                                    .background(Color.clear)
                                    .buttonStyle(.plain)
                                    .focusable(true) { focus in
                                        if focus {
                                            liveViewModel.showOverlay = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: {
                                                focusState = .leftMenu(0, 0)
                                            })
                                        }
                                    }
                                }
                                
                                .frame(width: liveViewModel.showOverlay == true ? 150: 300, height: liveViewModel.showOverlay == true ? liveViewModel.leftMenuMinHeight:  liveViewModel.leftMenuMaxHeight)
                            }
                            .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftMenuMaxHeight)
                            Spacer()
                        }
                        Spacer()
                    }
                    
                    .edgesIgnoringSafeArea(.all)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
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
        .simpleToast(isPresented: $liveModel.showToast, options: liveViewModel.toastOptions) {
            Label(liveViewModel.toastTitle, systemImage: liveViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                .padding()
                .background(liveViewModel.toastTypeIsSuccess ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
    }
    
}

