//
//  BiliBiliMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/9/14.
//

import SwiftUI
import Kingfisher
//
//let leftMenuNormalStateWidth = 130.0
//let leftMenuHighLightStateWidth = 330.0
//
//enum FocusAreas {
//    case leftMenu
//    case mainContent
//}

struct ListMainView: View {
    
    @State private var size: CGFloat = leftMenuNormalStateWidth
    @State private var leftMenuCurrentSelectIndex = -1
    @State private var leftMenuShowSubList = false
    @FocusState var focusState: FocusAreas?
    @FocusState var mainContentfocusState: Int?
    @State private var roomContentArray: Array<LiveModel> = []
    @State private var page = 1
    @State private var currentCategoryModel: Any?
    @State public var liveType: LiveType
    
    var body: some View {
        HStack {
            LeftMenu(liveType:liveType, size: $size, currentIndex: $leftMenuCurrentSelectIndex, isShowSubList: $leftMenuShowSubList, leftMenuDidClick: { _, _, categoryModel in
                page = 1
                currentCategoryModel = categoryModel
                getRoomList()
            })
                .cornerRadius(20)
                .focused($focusState, equals: .leftMenu)
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                    ForEach(roomContentArray.indices, id: \.self) { index in
                        LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index)
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
    }
    
    func getRoomList() {
        Task {
            if currentCategoryModel == nil {
                return
            }

            if liveType == .bilibili {
                let res = try await Bilibili.getCategoryRooms(category: currentCategoryModel as! BilibiliCategoryModel, page: page)
                DispatchQueue.main.async {
                    
                    if page == 1 {
                        roomContentArray = []
                    }
                    roomContentArray += res
                }
            }else if liveType == .douyin {
                let partitionId = (currentCategoryModel as! DouyinCategoryData).partition.id_str
                let partitionType = (currentCategoryModel as! DouyinCategoryData).partition.type
                let res = try await Douyin.getDouyinCategoryList(partitionId: partitionId, partitionType: partitionType, page: page)
                if page == 1 {
                    roomContentArray.removeAll()
                }
                roomContentArray += res
            }else if liveType == .douyu {
                let res = try await Douyu.getCategoryRooms(category: currentCategoryModel as! DouyuSubListModel, page: page)
                if page == 1 {
                    roomContentArray.removeAll()
                }
                roomContentArray += res
            }else if liveType == .huya {
                let res = try await Huya.getCategoryRooms(category: currentCategoryModel as! HuyaSubListModel, page: page)
                if page == 1 {
                    roomContentArray.removeAll()
                }
                roomContentArray += res
            }
        }
    }
    
    
}
