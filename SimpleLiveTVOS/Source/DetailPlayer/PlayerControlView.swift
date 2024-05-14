//
//  PlayerControlView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/27.
//

import SwiftUI
import SimpleToast
import KSPlayer

struct PlayerControlView: View {
    
    var roomInfoViewModel: RoomInfoStore
    var danmuSettingModel: DanmuSettingModel
    @EnvironmentObject var favoriteModel: FavoriteModel
    @FocusState var leftFocusState: Bool
    @FocusState var rightFocusState: Bool
    @FocusState var playFocusState: Bool
    @FocusState var danmuFocusState: Bool
    
    let topGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.1)]),
        startPoint: .top,
        endPoint: .bottom
    )
    let bottomGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.5)]),
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        
        @Bindable var roomInfoModel = roomInfoViewModel
        
        VStack() {
            HStack {
                Text("\(roomInfoViewModel.currentRoom.userName) - \(roomInfoViewModel.currentRoom.roomTitle)")
                    .font(.title3)
                    .padding(.leading, 15)
                    .foregroundStyle(.white)
                Spacer()
            }
            .background {
                Rectangle()
                    .fill(topGradient)
                    .shadow(radius: 10)
                    .frame(height: 150)
            }
            .frame(height: 150)
            HStack {
                Spacer()
                if roomInfoViewModel.debugTimerIsActive {
                    VStack {
                        Text("Display FPS:\(roomInfoViewModel.dynamicInfo!.displayFPS)")
                        LabeledContent("Display FPS", value: roomInfoViewModel.dynamicInfo!.displayFPS, format: .number)
//                        LabeledContent("Audio Video sync", value: roomInfoViewModel.dynamicInfo!.audioVideoSyncDiff, format: .number)
//                        LabeledContent("Dropped Frames", value: roomInfoViewModel.dynamicInfo!.droppedVideoFrameCount + roomInfoViewModel.dynamicInfo!.droppedVideoPacketCount, format: .number)
//                        LabeledContent("Bytes Read", value: roomInfoViewModel.dynamicInfo!.bytesRead.kmFormatted + "B")
//                        LabeledContent("Audio bitrate", value: roomInfoViewModel.dynamicInfo!.audioBitrate.kmFormatted + "bps")
//                        LabeledContent("Video bitrate", value: roomInfoViewModel.dynamicInfo!.videoBitrate.kmFormatted + "bps")
                    }
                }
            }
            Spacer()
            HStack(alignment: .center, spacing: 15) {
                Button(action: {}, label: {
                    
                })
                .padding(.leading, -80)
                .clipShape(.circle)
                .frame(width: 40, height: 40)
                .focused($leftFocusState)
                Button(action: {
                    if (roomInfoViewModel.showControlView == false) {
                        roomInfoViewModel.showControlView = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                            if roomInfoViewModel.showControlView == true {
                                roomInfoViewModel.showControlView = false
                            }
                        })
                    }else {
                        if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false {
                            roomInfoViewModel.playerCoordinator.playerLayer?.pause()
                        }else {
                            roomInfoViewModel.playerCoordinator.playerLayer?.play()
                        }
                    }
                }, label: {
                    Image(systemName: roomInfoViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                })
                .focusSection()
                .contextMenu(menuItems: {
                    Button("debug mode") {
//                        roomInfoViewModel.toggleTimer()
                    }
                })
                .focused($playFocusState)
                .clipShape(.circle)
                .padding(.leading, -20)
                Button(action: {
                    if (roomInfoViewModel.showControlView == false) {
                        roomInfoViewModel.showControlView = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                            if roomInfoViewModel.showControlView == true {
                                roomInfoViewModel.showControlView = false
                            }
                        })
                    }else {
                        roomInfoViewModel.getPlayArgs()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                            if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false == false {
                                roomInfoViewModel.playerCoordinator.playerLayer?.play()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                                    roomInfoViewModel.showControlView = false
                                })
                            }
                        })
                    }
                }, label: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundColor(.white)
                        .font(.system(size: 30, weight: .bold))
                        .frame(width: 40, height: 40)
                })
                .clipShape(.circle)
                .padding(.leading, -20)
                Button(action: {
                    if (roomInfoViewModel.showControlView == false) {
                        roomInfoViewModel.showControlView = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                            if roomInfoViewModel.showControlView == true {
                                roomInfoViewModel.showControlView = false
                            }
                        })
                    }else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            favoriteAction()
                        }
                    }
                }, label: {
                    Image(systemName:  favoriteModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) ? "heart.fill" : "heart")
                        .foregroundColor(favoriteModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) ? .red : .white)
                        .font(.system(size: 30, weight: .bold))
                        .frame(width: 40, height: 40)
                        .padding(.top, 3)
                        .contentTransition(.symbolEffect(.replace))
                })
                .clipShape(.circle)
                .padding(.leading, -20)
                Color.green
                    .cornerRadius(10)
                    .frame(width: 20, height: 20)
                Text("Live")
                    .foregroundStyle(.white)
                Spacer()
                Menu {
                    ForEach(roomInfoViewModel.currentRoomPlayArgs?.indices ?? 0..<1, id: \.self) { index in
                        Button(action: {
                            if (roomInfoViewModel.showControlView == false) {
                                roomInfoViewModel.showControlView = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                                    if roomInfoViewModel.showControlView == true {
                                        roomInfoViewModel.showControlView = false
                                    }
                                })
                            }else {}
                        }, label: {
                            if roomInfoViewModel.currentRoomPlayArgs == nil {
                                Text("测试")
                            }else {
                                Menu {
                                    ForEach(roomInfoViewModel.currentRoomPlayArgs?[index].qualitys.indices ?? 0 ..< 1, id: \.self) { subIndex in
                                        Button {
                                            roomInfoViewModel.changePlayUrl(cdnIndex: index, urlIndex: subIndex)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                                                if roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false == false {
                                                    roomInfoViewModel.playerCoordinator.playerLayer?.play()
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                                                        roomInfoViewModel.showControlView = false
                                                    })
                                                }
                                            })
                                        } label: {
                                            Text(roomInfoViewModel.currentRoomPlayArgs?[index].qualitys[subIndex].title ?? "")
                                        }
                                    }
                                } label: {
                                    Text(roomInfoViewModel.currentRoomPlayArgs?[index].cdn ?? "")
                                }
                            }
                        })
                    }
                } label: {
                    Text(roomInfoViewModel.currentPlayQualityString)
                        .font(.system(size: 30, weight: .bold))
                        .frame(height: 50, alignment: .center)
                        .padding(.top, 10)
                        .foregroundStyle(.white)
                }
                .frame(height: 60)
                .clipShape(.capsule)
                
                Button(action: {
                    if (roomInfoViewModel.showControlView == false) {
                        roomInfoViewModel.showControlView = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: {
                            if roomInfoViewModel.showControlView == true {
                                roomInfoViewModel.showControlView = false
                            }
                        })
                    }else {
                        danmuSettingModel.showDanmu.toggle()
                        if danmuSettingModel.showDanmu == false {
                            roomInfoViewModel.disConnectSocket()
                        }else {
                            roomInfoViewModel.getDanmuInfo()
                        }
                    }
                }, label: {
                    Image(danmuSettingModel.showDanmu ? "icon-danmu-open-focus" : "icon-danmu-close-focus")
                        .resizable()
                        .frame(width: 40, height: 40)
                })
                .focused($danmuFocusState)
                .focusSection()
                .clipShape(.circle)
                
                Button(action: {}, label: {
                    
                })
                .focused($rightFocusState)
                .padding(.trailing, 110)
                .clipShape(.circle)
                .frame(width: 40, height: 40)
            }
            .onAppear {
                playFocusState = true
            }
            .onChange(of: leftFocusState, { oldValue, newValue in
                if leftFocusState == true {
                    danmuFocusState = true
                }
            })
            .onChange(of: rightFocusState, { oldValue, newValue in
                if rightFocusState == true {
                    playFocusState = true
                }
            })
            .background {
                Rectangle()
                    .fill(bottomGradient)
                    .shadow(radius: 10)
                    .frame(height: 150)
            }
            .frame(height: 150)
        }
        .onReceive(roomInfoViewModel.timer, perform: { _ in
//            roomInfoViewModel.dynamicInfo = roomInfoViewModel.playerCoordinator.playerLayer?.player.dynamicInfo
        })
        .simpleToast(isPresented: $roomInfoModel.showToast, options: roomInfoViewModel.toastOptions) {
            Label(roomInfoViewModel.toastTitle, systemImage: roomInfoViewModel.toastTypeIsSuccess ? "checkmark.circle" : "xmark.circle")
                .padding()
                .background(roomInfoViewModel.toastTypeIsSuccess ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
    }
    
    func favoriteAction() {
        if favoriteModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) == false {
            Task {
                try await favoriteModel.addFavorite(room: roomInfoViewModel.currentRoom)
                roomInfoViewModel.showToast(true, title: "收藏成功")
            }
        }else {
            Task {
                try await  favoriteModel.removeFavoriteRoom(room: roomInfoViewModel.currentRoom)
                roomInfoViewModel.showToast(true, title: "取消收藏成功")
            }
        }
    }
}

//#Preview {
//    PlayerControlView()
//        .environmentObject(LiveStore(roomListType: .live, liveType: .bilibili))
//}
