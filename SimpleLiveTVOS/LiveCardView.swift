//
//  LiveCardView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/9.
//

import SwiftUI
import Kingfisher

struct LiveCardView: View {
    
    @Binding var liveModel: LiveModel
    @FocusState var mainContentfocusState: Int?
    @State var index: Int
    @State var isFavorite = false
    @State private var showAlert = false
    var showToast: (Bool, Bool, String) -> Void = { _,_,_   in }
    
    var body: some View {
        NavigationLink {
            if liveModel.liveType == .douyu || liveModel.liveType == .huya {
                KSAudioView(roomModel: liveModel)
                    .edgesIgnoringSafeArea(.all)
            }else {
                PlayerView(roomModel: liveModel, liveType: liveModel.liveType)
                    .edgesIgnoringSafeArea(.all)
            }
        } label: {
            VStack(spacing: 10, content: {
                ZStack(alignment: Alignment(horizontal: .leading, vertical: .top), content: {
                    KFImage(URL(string: liveModel.roomCover))
                        .resizable()
                        .frame(width: 320, height: 180)
                    if isFavorite {
                        HStack{
                            Image(uiImage: .init(named: getImage())!)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .background(liveModel.liveType == .bilibili ? Color.black.opacity(0.3) : Color.clear)
                                .cornerRadius(5)
                                .padding(.top, 5)
                                .padding(.leading, 5)
                            Spacer()
                            HStack(spacing: 5) {
                                
                                if liveModel.liveState ?? "" == "" {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                }else {
                                    Circle()
                                        .fill(liveModel.liveState ?? "" == "正在直播" ? Color.green : Color.gray)
                                        .frame(width: 10, height: 10)
                                    Text(liveModel.liveState ?? "")
                                        .font(.system(size: 18))
                                }
                            }
                            .padding(.trailing, 5)
                        }
                    }
                })
                .frame(width: 320, height: 180)
                HStack {
                    KFImage(URL(string: liveModel.userHeadImg))
                            .resizable()
                            .frame(width: 40, height: 40)
                            .cornerRadius(20)
                    VStack (alignment: .leading, spacing: 10) {
                        Text(liveModel.userName)
                            .font(.system(size: liveModel.userName.count > 5 ? 19 : 24))
                            .padding(.top, 10)
                            .frame(width: 200, height: liveModel.userName.count > 5 ? 19 : 24, alignment: .leading)
                        Text(liveModel.roomTitle)
                            .font(.system(size: 15))
                            .frame(width: 200, height: 15 ,alignment: .leading)
                    }
                    .padding(.trailing, 0)
                    .padding(.leading, -35)
                   
                }
                Spacer(minLength: 0)
            })
            
        }
        .buttonStyle(.card)
        .focused($mainContentfocusState, equals: index)
        .focusSection()
        .alert("提示", isPresented: $showAlert) {
            Button("取消收藏", role: .destructive, action: cancelFavoriteAction)
            Button("再想想",role: .cancel) {
                showAlert = false
            }
        } message: {
            Text("确认取消收藏吗")
        }
        .contextMenu(menuItems: {
            if SQLiteManager.manager.search(roomId: liveModel.roomId) != nil {
                Button(action: {
                    showAlert = true
                }, label: {
                    HStack {
                        Image(systemName: "heart.fill")
                        Text("取消收藏")
                    }
                })
                
            }else {
                Button(action: favoriteAction, label: {
                    HStack {
                        Image(systemName: "heart.fill")
                        Text("收藏")
                    }
                })
            }
        })
        .task {
            do {
                if isFavorite == true {
                    try await liveModel.getLiveState()
                }
            }catch {
                
            }
        }
    }
    
    func favoriteAction() {
        if SQLiteManager.manager.insert(item: liveModel) {
            self.showToast(true, false, "收藏成功")
        }else {
            self.showToast(false, false, "收藏失败")
        }
    }
    
    func cancelFavoriteAction() {
        if SQLiteManager.manager.delete(roomId: liveModel.roomId) {
            self.showToast(true, true, "取消收藏成功")
        }else {
            self.showToast(false, true, "取消收藏失败")
        }
    }
    
    func getImage() -> String {
        switch liveModel.liveType {
            case .bilibili:
                return "bilibili"
            case .douyu:
                return "douyu"
            case .huya:
                return "huya"
            default:
                return "douyin"
        }
    }
}
