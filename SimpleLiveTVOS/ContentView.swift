//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import Kingfisher


let leftMenuNormalStateWidth = 130.0
let leftMenuHighLightStateWidth = 330.0

enum FocusAreas {
    case leftMenu
    case mainContent
}

struct ContentView: View {
    @State private var size: CGFloat = leftMenuNormalStateWidth
    @State private var leftMenuCurrentSelectIndex = -1
    @State private var leftMenuShowSubList = false
    @FocusState var focusState: FocusAreas?
    @FocusState var focusState2: Int?
    @State private var roomContentArray: Array<BiliBiliCategoryListModel> = []
    @State private var page = 1
    @State private var currentCategoryModel: BilibiliCategoryModel?
    
    var body: some View {
        NavigationView {
            TabView {
                HStack {
                    LeftMenu(size: $size, currentIndex: $leftMenuCurrentSelectIndex, isShowSubList: $leftMenuShowSubList, leftMenuDidClick: { _, _, categoryModel in
                        page = 1
                        currentCategoryModel = categoryModel
                        getRoomList()
                    })
                        .cornerRadius(20)
                        .focused($focusState, equals: .leftMenu)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                            ForEach(roomContentArray.indices, id: \.self) { index in
                                NavigationLink {
                                    PlayerView(roomModel: roomContentArray[index])
                                        .edgesIgnoringSafeArea(.all)
                                } label: {
    //                                Button(action: {
    //                                    goToPlaylist(roomModel: roomContentArray[index])
    //                                }) {
    //
    //                                }
    //                                .buttonStyle(CardButtonStyle())
                                    VStack {
                                        KFImage(URL(string: roomContentArray[index].user_cover))
                                            .resizable()
                                            .frame(width: 320, height: 180)
                                        Text(roomContentArray[index].uname)
                                            .background(Color.clear)
                                    }
                                }
                                .buttonStyle(.card)
                                .focused($focusState2, equals: index)
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
                .onChange(of: focusState2, perform: { newValue in
                    if newValue ?? 0 > self.roomContentArray.count - 6 {
                        page += 1
                        getRoomList()
                    }
                })
                
                .tabItem {
                    Label("收藏", systemImage: "heart.fill")
                }
                ZStack {
                    
                }
                .tabItem {
                    Label("bilibi", image: "bilibili")
                }
                ZStack {
                    
                }
                .tabItem {
                    Label("虎牙", image: "huya")
                }
                ZStack {
                    
                }
                .tabItem {
                    Label("斗鱼", image: "douyu")
                }
                ZStack {
                    
                }
                .tabItem {
                    Label("企鹅", image: "egame")
                }
                ZStack {
                    
                }
                .tabItem {
                    Label("抖音", image: "douyin")
                }
            }
        }
    }
    
    
    func goToPlaylist(roomModel: BiliBiliCategoryListModel) {

    }
    
    func getRoomList() {
        Task {
            let res = try await Bilibili.getCategoryRooms(category: currentCategoryModel!, page: page)
            if res.code == 0 {
                if let listModelArray = res.data.list {
                    for listModel in listModelArray {
                        roomContentArray.append(listModel)
                    }
                }
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
