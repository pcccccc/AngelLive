//
//  DouyinMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/9/14.
//

import SwiftUI
import Kingfisher

struct DouyinMainView: View {
    
    @State private var mainList = [DouyinCategoryData]()
    @State private var size: CGFloat = leftMenuNormalStateWidth
    @State private var leftMenuCurrentSelectIndex = -1
    @State private var leftMenuShowSubList = false
    @FocusState var focusState: FocusAreas?
    @FocusState var mainContentfocusState: Int?
    @State private var roomContentArray: Array<DouyinStreamerData> = []
    @State private var page = 1
    @State private var currentCategoryModel: DouyinCategoryData?
    
    var body: some View {
        HStack {
            LeftMenu(liveType: .douyin, size: $size, currentIndex: $leftMenuCurrentSelectIndex, isShowSubList: $leftMenuShowSubList, leftMenuDidClick: { _, _, categoryModel in
                page = 1
                currentCategoryModel = categoryModel as? DouyinCategoryData
                getRoomList()
            })
                .cornerRadius(20)
                .focused($focusState, equals: .leftMenu)
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                    ForEach(roomContentArray.indices, id: \.self) { index in
                        NavigationLink {
                            
                            PlayerView(roomModel: roomContentArray[index], liveType: .douyin)
                                .edgesIgnoringSafeArea(.all)
                        } label: {
    //                                Button(action: {
    //                                    goToPlaylist(roomModel: roomContentArray[index])
    //                                }) {
    //
    //                                }
    //                                .buttonStyle(CardButtonStyle())
                            VStack(spacing: 10, content: {
                                KFImage(URL(string: roomContentArray[index].room.cover.url_list.last ?? ""))
                                    .resizable()
                                    .frame(width: 320, height: 180)
                                    
                                HStack {
                                    KFImage(URL(string: roomContentArray[index].room.owner.avatar_thumb.url_list.last ?? ""))
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(20)
                                        
                                    VStack (alignment: .leading, spacing: 10) {
                                        Text(roomContentArray[index].room.owner.nickname)
                                            .font(.system(size: roomContentArray[index].room.owner.nickname.count > 5 ? 19 : 24))
                                            .padding(.top, 10)
                                            .frame(width: 200, height: roomContentArray[index].room.owner.nickname.count > 5 ? 19 : 24, alignment: .leading)
                                        Text(roomContentArray[index].room.title)
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
            Task {
                do {
                   
                    self.mainList = try await Douyin.getDouyinList()
                }catch {
                    print(error)
                }
            }
        }
    }
    
    func getRoomList() {
        Task {
            
            do {
                let partitionId = currentCategoryModel?.partition.id_str ?? ""
                let partitionType = currentCategoryModel?.partition.type ?? 0
                print("当前partitionId\(partitionId)")
                let res = try await Douyin.getDouyinCategoryList(partitionId: partitionId, partitionType: partitionType, page: page)
                let listModelArray = res.data
                if page == 1 {
                    roomContentArray.removeAll()
                }
                for listModel in listModelArray {
                    roomContentArray.append(listModel)
                }
            }catch {
                print("-----error:\(error)")
            }
        }
    }
}

struct DouyinMainView_Previews: PreviewProvider {
    static var previews: some View {
        DouyinMainView()
    }
}
