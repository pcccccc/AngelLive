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
    
    var body: some View {
        NavigationLink {
            if liveModel.liveType == .douyu {
                KSAudioView(roomModel: liveModel)
                    .edgesIgnoringSafeArea(.all)
            }else {
                PlayerView(roomModel: liveModel, liveType: liveModel.liveType)
                    .edgesIgnoringSafeArea(.all)
            }
        } label: {
            VStack(spacing: 10, content: {
                KFImage(URL(string: liveModel.roomCover))
                    .resizable()
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
        .contextMenu(menuItems: {
            Button(action: favoriteAction, label: {
                Text("收藏")
            })
            
        })
    }
    
    func favoriteAction (){
        
    }
}

//#Preview {
//    LiveCardView()
//}
