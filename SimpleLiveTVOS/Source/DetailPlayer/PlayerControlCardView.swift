//
//  PlayerControlCardView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/8/23.
//

import SwiftUI
import Kingfisher
import LiveParse

struct PlayerControlCardView: View {
    
    @Environment(PlayerControlCardViewModel.self) var playControlCardViewModel
    @FocusState var topState: PlayControlTopField?
    let changeRoom: (LiveModel) -> Void
    
    let cardGradient = LinearGradient(stops: [
        .init(color: .black.opacity(0.5), location: 0.0),
        .init(color: .black.opacity(0.25), location: 0.45),
        .init(color: .black.opacity(0), location: 0.8)
    ], startPoint: .bottom, endPoint: .top)
    
    var body: some View {
        VStack {
            Button {
                changeRoom(playControlCardViewModel.liveModel)
            } label: {
                ZStack(alignment: .bottom) {
                    KFImage(URL(string: playControlCardViewModel.liveModel.roomCover))
                        .placeholder {
                            Image("placeholder")
                                .resizable()
                                .frame(width: 320, height: 210)
                        }
                        .resizable()
                        .frame(width: 320, height: 210)
                        .blur(radius: 10)
                    KFImage(URL(string: playControlCardViewModel.liveModel.roomCover))
                        .placeholder {
                            Image("placeholder")
                                .resizable()
                                .frame(width: 320, height: 210)
                        }
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 210)
                        .background(.thinMaterial)
                    Rectangle()
                    .fill(cardGradient)
                    .shadow(radius: 10)
                    .frame(height: 40)
                    if playControlCardViewModel.liveModel.liveWatchedCount != nil {
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "eye")
                                    .font(.system(size: 14))
                                Text(playControlCardViewModel.liveModel.liveWatchedCount!.formatWatchedCount())
                                    .font(.system(size: 18))
                            }
                            .foregroundColor(.white)
                            .padding([.trailing], 10)
                        }
                        .frame(height: 30, alignment: .trailing)
                    }
                    if playControlCardViewModel.selectIndex != 2 { // 如果不为直播页面，则展示对应平台和直播状态
                        HStack {
                            Image(uiImage: .init(named: Common.getImage(playControlCardViewModel.liveModel.liveType))!)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(5)
                                .padding(.top, 5)
                                .padding(.leading, 5)
                            Spacer()
                            if playControlCardViewModel.liveStateLoading == true {
                                HStack {
                                    ProgressView()
                                        .frame(width: 15, height: 15)
                                }
                                .frame(width: 40)
                                .padding(.trailing, 15)
                            }else {
                                if playControlCardViewModel.liveModel.liveState != "" {
                                    HStack(spacing: 5) {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(LiveState(rawValue: playControlCardViewModel.liveModel.liveState ?? "3") == .live ? Color.green : Color.gray)
                                                .frame(width: 10, height: 10)
                                                .padding(.leading, 5)
                                            Text(playControlCardViewModel.liveModel.liveStateFormat())
                                                .font(.system(size: 18))
                                                .foregroundColor(Color.white)
                                                .padding(.trailing, 5)
                                                .padding(.top, 5)
                                                .padding(.bottom, 5)
                                        }
                                        .background(Color("favorite_right_hint"))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .padding(.trailing, 5)
                                }else {
                                    HStack { //占位防止成为焦点飘移
                                        
                                    }
                                    .frame(width: 40)
                                    .padding(.trailing, 15)
                                }
                            }
                        }
                        .padding(.bottom, 165)
                    }
                }
            }
            .buttonStyle(.card)
            .focused($topState, equals: .list(playControlCardViewModel.cardIndex))
            .padding(.leading, 15)
            Text("\(playControlCardViewModel.liveModel.userName) - \(playControlCardViewModel.liveModel.roomTitle)")
                .font(.system(size: 22))
                .opacity(topState == .list(playControlCardViewModel.cardIndex) ? 1 : 0)
                .transition(.opacity)
                .frame(width: 360)
                .foregroundColor(.white)
                .padding(.leading, 15)
                .padding(.top, 10)
                .animation(.easeInOut(duration: 0.25), value: topState == .list(playControlCardViewModel.cardIndex))
//                                .focused($state, equals: .listContent(i))
        }
        .onChange(of: topState) { oldValue, newValue in
            switch newValue {
            case .list(_):
                    if playControlCardViewModel.liveModel.liveState == nil || playControlCardViewModel.liveModel.liveState == LiveState.unknow.rawValue || playControlCardViewModel.liveModel.liveState == "" {
                        playControlCardViewModel.liveStateLoading = true
                        Task {
                            let resp = try await ApiManager.fetchLastestLiveInfo(liveModel: playControlCardViewModel.liveModel)
                            playControlCardViewModel.liveModel.liveState = resp.liveState
                            playControlCardViewModel.liveStateLoading = false
                        }
                    }
                default:
                    break
            }
        }
        
    }
}
