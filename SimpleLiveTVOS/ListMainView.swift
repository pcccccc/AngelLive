//
//  BiliBiliMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/9/14.
//

import SwiftUI
import Kingfisher
import SimpleToast

let leftMenuNormalStateWidth = 130.0
let leftMenuHighLightStateWidth = 330.0

enum FocusAreas {
    case leftMenu
    case mainContent
}

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
    @State var showToast: Bool = false
    @State var toastTitle: String = ""
    @State var toastTypeIsSuccess: Bool = false
    @State var loadingText: String = "正在获取内容"
    @State var needFullScreenLoading: Bool = false
    private static let topId = "topIdHere"
    private let toastOptions = SimpleToastOptions(
        hideAfter: 2
    )
    
    var body: some View {
        ZStack(alignment: .top) {
            if needFullScreenLoading == true {
                GeometryReader { proxy in
                    LoadingView(loadingText: $loadingText)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .zIndex(1)
            }
            HStack(spacing: 15) {
                LeftMenu(liveType:liveType, size: $size, currentIndex: $leftMenuCurrentSelectIndex, isShowSubList: $leftMenuShowSubList, leftMenuDidClick: { _, _, categoryModel in
                    page = 1
                    currentCategoryModel = categoryModel
                    getRoomList()
                })
                .cornerRadius(20)
                .focused($focusState, equals: .leftMenu)
                ScrollViewReader { reader in
                    ScrollView {
                        ZStack {
                            
                        }.id(Self.topId)
                        LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                            ForEach(0..<roomContentArray.count, id: \.self) { index in
                                autoreleasepool {
                                    LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, showLoading: { loadingText in
                                        self.loadingText = loadingText
                                        needFullScreenLoading = true
                                    }, showToast: { success, delete, hint in
                                        toastTypeIsSuccess = success
                                        toastTitle = hint
                                        needFullScreenLoading = false
                                        showToast.toggle()
                                    })
                                    
                                }
                            }
                        }
                    }
                    .onPlayPauseCommand(perform: {
                        page = 1
                        getRoomList()
                    })
                    
                }
                
            }
            .blur(radius: needFullScreenLoading == true ? 10 : 0)
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
            if newValue ?? 0 > 6 && newValue ?? 0 > self.roomContentArray.count - 6 {
                page += 1
                getRoomList()
            }
        })
        .simpleToast(isPresented: $showToast, options: toastOptions) {
            Label(toastTitle, systemImage: "checkmark.circle")
                .padding()
                .background(toastTypeIsSuccess == true ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
        }
        
    }
    
    func getRoomList() {
        Task {
            if currentCategoryModel == nil {
                return
            }
            
            if liveType == .bilibili {
                let res = try await Bilibili.getCategoryRooms(category: currentCategoryModel as! BilibiliCategoryModel, page: page)
                if page == 1 {
                    roomContentArray.removeAll()
                    toastTypeIsSuccess = true
                    toastTitle = "已为您获取最新内容"
                    showToast.toggle()
                }
                roomContentArray += res
                if page == 1 {
                    mainContentfocusState = 0
                }
            }else if liveType == .douyin {
                let partitionId = (currentCategoryModel as! DouyinCategoryData).partition.id_str
                let partitionType = (currentCategoryModel as! DouyinCategoryData).partition.type
                let res = try await Douyin.getDouyinCategoryList(partitionId: partitionId, partitionType: partitionType, page: page)
                if page == 1 {
                    roomContentArray.removeAll()
                    toastTypeIsSuccess = true
                    toastTitle = "已为您获取最新内容"
                    showToast.toggle()
                }
                roomContentArray += res
                if page == 1 {
                    mainContentfocusState = 0
                }
            }else if liveType == .douyu {
                let res = try await Douyu.getCategoryRooms(category: currentCategoryModel as! DouyuSubListModel, page: page)
                if page == 1 {
                    roomContentArray.removeAll()
                    toastTypeIsSuccess = true
                    toastTitle = "已为您获取最新内容"
                    showToast.toggle()
                   
                }
                roomContentArray += res
                if page == 1 {
                    mainContentfocusState = 0
                }
            }else if liveType == .huya {
                let res = try await Huya.getCategoryRooms(category: currentCategoryModel as! HuyaSubListModel, page: page)
                if page == 1 {
                    roomContentArray.removeAll()
                    toastTypeIsSuccess = true
                    toastTitle = "已为您获取最新内容"
                    showToast.toggle()
                }
                roomContentArray += res
                if page == 1 {
                    mainContentfocusState = 0
                }
            }
        }
    }
    
    
}

