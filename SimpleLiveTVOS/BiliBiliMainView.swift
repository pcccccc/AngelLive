//
//  BiliBiliMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/9/14.
//

import SwiftUI
import Kingfisher

let leftMenuNormalStateWidth = 130.0
let leftMenuHighLightStateWidth = 330.0

enum FocusAreas {
    case leftMenu
    case mainContent
}

struct BiliBiliMainView: View {
    
    @State private var size: CGFloat = leftMenuNormalStateWidth
    @State private var leftMenuCurrentSelectIndex = -1
    @State private var leftMenuShowSubList = false
    @FocusState var focusState: FocusAreas?
    @FocusState var mainContentfocusState: Int?
    @State private var roomContentArray: Array<BiliBiliCategoryListModel> = []
    @State private var page = 1
    @State private var currentCategoryModel: BilibiliCategoryModel?
    
    var body: some View {
        HStack {
            LeftMenu(liveType:.bilibili, size: $size, currentIndex: $leftMenuCurrentSelectIndex, isShowSubList: $leftMenuShowSubList, leftMenuDidClick: { _, _, categoryModel in
                page = 1
                currentCategoryModel = categoryModel as? BilibiliCategoryModel
                getRoomList()
            })
                .cornerRadius(20)
                .focused($focusState, equals: .leftMenu)
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                    ForEach(roomContentArray.indices, id: \.self) { index in
                        NavigationLink {
                            PlayerView(roomModel: roomContentArray[index], liveType: .bilibili)
                                .edgesIgnoringSafeArea(.all)
                        } label: {
//                                Button(action: {
//                                    goToPlaylist(roomModel: roomContentArray[index])
//                                }) {
//
//                                }
//                                .buttonStyle(CardButtonStyle())
                            VStack(spacing: 10, content: {
                                KFImage(URL(string: roomContentArray[index].user_cover))
                                    .resizable()
                                    .frame(width: 320, height: 180)
                                    
                                HStack {
                                    KFImage(URL(string: roomContentArray[index].face))
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(20)
                                        
                                    VStack (alignment: .leading, spacing: 10) {
                                        Text(roomContentArray[index].uname)
                                            .font(.system(size: roomContentArray[index].uname.count > 5 ? 19 : 24))
                                            .padding(.top, 10)
                                            .frame(width: 200, height: roomContentArray[index].uname.count > 5 ? 19 : 24, alignment: .leading)
                                        Text(roomContentArray[index].title)
                                            .font(.system(size: 15))
//                                                    .padding(.bottom, 10)
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
                    }
                }
            }
        }
        .onChange(of: focusState, perform: { newFocus in
            if newFocus == .leftMenu {
                withAnimation {
                    size = leftMenuHighLightStateWidth
                }
            }else {
                withAnimation {
                    size = leftMenuNormalStateWidth
                    leftMenuCurrentSelectIndex = -1
                    leftMenuShowSubList = false
                }
            }
        })
        .onChange(of: mainContentfocusState, perform: { newValue in
            if newValue ?? 0 > self.roomContentArray.count - 6 {
                page += 1
                getRoomList()
            }
        })
        .onAppear {
            
        }
    }
    
    func goToPlaylist(roomModel: BiliBiliCategoryListModel) {

    }
    
    func getRoomList() {
        Task {
            let res = try await Bilibili.getCategoryRooms(category: currentCategoryModel!, page: page)
            if res.code == 0 {
                if let listModelArray = res.data.list {
                    if page == 1 {
                        roomContentArray.removeAll()
                    }
                    for listModel in listModelArray {
                        roomContentArray.append(listModel)
                    }
                }
            }
            
        }
    }
}

struct BiliBiliMainView_Previews: PreviewProvider {
    static var previews: some View {
        BiliBiliMainView()
    }
}
