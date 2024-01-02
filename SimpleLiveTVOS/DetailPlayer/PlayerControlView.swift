//
//  PlayerControlView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/12/27.
//

import SwiftUI

struct PlayerControlView: View {
    
    @StateObject var danmuSetting = SettingStore()
    @EnvironmentObject var roomInfoViewModel: RoomInfoStore
    @FocusState var isFocused: Bool
    let gradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.5)]),
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        VStack() {
            HStack {
                Text(roomInfoViewModel.currentRoom.roomTitle)
                    .font(.title2)
                Spacer()
            }
            Spacer()
            HStack(alignment: .center, spacing: 15) {
                Button(action: {
                    
                }, label: {
                    Image(systemName: roomInfoViewModel.playerCoordinator.playerLayer?.player.isPlaying ?? false ? "pause.fill" : "play.fill")
                        .frame(width: 40, height: 40)
                })
                .clipShape(.circle)
                Color.green
                    .cornerRadius(10)
                    .frame(width: 20, height: 20)
                Text("Live")
                Spacer()
                Menu {
                    ForEach(roomInfoViewModel.currentRoomPlayArgs?.indices ?? 0..<1, id: \.self) { index in
                        Button(action: {
                            
                        }, label: {
                            if roomInfoViewModel.currentRoomPlayArgs == nil {
                                Text("测试")
                            }else {
                                Menu {
                                    ForEach(roomInfoViewModel.currentRoomPlayArgs?[index].qualitys.indices ?? 0 ..< 1, id: \.self) { subIndex in
                                        Button {
                                            
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
                    Text("清晰度")
                        .font(.subheadline)
                        .bold()
                }
                .padding(.top, 55)
                .frame(height: 40)
                Button(action: {
                    danmuSetting.showDanmu.toggle()
                }, label: {
                    Image(danmuSetting.showDanmu ? "icon-danmu-open-normal" : "icon-danmu-open-focus")
                        .resizable()
                        .frame(width: 40, height: 40)
                        
                        
                })
                .clipShape(.circle)
            }
            .background {
                Rectangle()
                    .fill(gradient)
                    .shadow(radius: 10)
                    .frame(height: 100)
            }
            
            .edgesIgnoringSafeArea(.bottom)
        }
    }
}

#Preview {
    PlayerControlView()
        .environmentObject(LiveStore(roomListType: .live, liveType: .bilibili))
}
