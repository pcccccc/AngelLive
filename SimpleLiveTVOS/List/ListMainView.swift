//
//  BiliBiliMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/9/14.
//

import SwiftUI
import Kingfisher
import SimpleToast
import LiveParse

let leftMenuNormalStateWidth = 130.0
let leftMenuHighLightStateWidth = 330.0

enum FocusableField: Hashable {
    case leftMenu(Int)
    case mainContent(Int)
}

struct ListMainView: View {

    @State var showToast: Bool = false
    @State var toastTitle: String = ""
    @State var toastTypeIsSuccess: Bool = false
    @State var loadingText: String = "正在获取内容"
    @State var needFullScreenLoading: Bool = false
    private static let topId = "topIdHere"
    private let toastOptions = SimpleToastOptions(
        hideAfter: 2
    )
    
    var liveType: LiveType
    @StateObject var liveListViewModel: LiveListViewModel
    @FocusState var focusState: FocusableField?
    
    init(liveType: LiveType) {
        self.liveType = liveType
        self._liveListViewModel = StateObject(wrappedValue: LiveListViewModel(liveType: liveType))
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                ZStack {
                }
                .id(Self.topId)
                LazyVGrid(columns: [GridItem(.fixed(400)), GridItem(.fixed(400)), GridItem(.fixed(400)), GridItem(.fixed(400))], spacing: 35) {
                    ForEach(liveListViewModel.roomList.indices, id: \.self) { index in
//                        LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, showLoading: { loadingText in
//                            self.loadingText = loadingText
//                            needFullScreenLoading = true
//                        }, showToast: { success, delete, hint in
//                            toastTypeIsSuccess = success
//                            toastTitle = hint
//                            needFullScreenLoading = false
//                            showToast.toggle()
//                        })
                        LiveCardView(index: index)
                            .environmentObject(liveListViewModel)
                            .onMoveCommand(perform: { direction in
                                switch direction {
//                                case .right:
//                                    liveListViewModel.showOverlay = false
                                case .left:
//                                    liveListViewModel.showOverlay = true
                                    if index % 4 == 0 {
                                        liveListViewModel.showOverlay = true
                                        focusState = .leftMenu(0)
                                    }
                                default:
                                    print(222)
                                }
                        })
                           
                            .frame(width: 400, height: 240)
                            
                    }
                }
            }.overlay {
                ZStack {
                    LeftMenu(focusState: _focusState)
                       .environmentObject(liveListViewModel)
                       .onMoveCommand(perform: { direction in
                           switch direction {
                           case .right:
                               liveListViewModel.showOverlay = false
                           case .left:
                               liveListViewModel.showOverlay = true
                           default:
                               print(222)
                           }
                       })
                       .offset(x: -(1920/2) + (liveListViewModel.leftWidth / 2), y: -(1080/2) + (liveListViewModel.leftHeight / 2))
                       
//                       .animation(.spring(duration: 1.0), value: liveListViewModel.leftWidth)
//                       .animation(.spring(duration: 1.0), value: liveListViewModel.leftHeight)
                }
//                .frame(minWidth: 1920 , maxWidth: .infinity, minHeight: 1080, maxHeight: .infinity)
//                .background(Color.black.opacity(0.5))
            }
        }
        
//        ScrollViewReader { reader in
//            ZStack(alignment: .top) {
//                if needFullScreenLoading == true {
//                    GeometryReader { proxy in
//                        LoadingView(loadingText: $loadingText)
//                            .frame(width: proxy.size.width, height: proxy.size.height)
//                    }
//                    .zIndex(1)
//                }
//                HStack(spacing: 15) {
////                    LeftMenu(liveType:liveType, size: $size, currentIndex: $leftMenuCurrentSelectIndex, isShowSubList: $leftMenuShowSubList, leftMenuDidClick: { _, _, categoryModel in
////                        page = 1
////                        currentCategoryModel = categoryModel
////                        getRoomList()
////                    })
////                    .cornerRadius(20)
////                    .focused($focusState, equals: .leftMenu)
//
//
//                    ScrollView {
//                        ZStack {
//
//                        }
//                        .id(Self.topId)
//                        LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
//                            ForEach(0..<roomContentArray.count, id: \.self) { index in
//                                LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, showLoading: { loadingText in
//                                    self.loadingText = loadingText
//                                    needFullScreenLoading = true
//                                }, showToast: { success, delete, hint in
//                                    toastTypeIsSuccess = success
//                                    toastTitle = hint
//                                    needFullScreenLoading = false
//                                    showToast.toggle()
//                                })
//                            }
//                        }
//                    }
//                }
//            }
//            .blur(radius: needFullScreenLoading == true ? 10 : 0)
//            .onPlayPauseCommand(perform: {
////                page = 1
////                getRoomList()
////                reader.scrollTo(Self.topId)
//            })
//        }
//        .onChange(of: focusState, perform: { newFocus in
//            if newFocus == .leftMenu {
//                withAnimation {
//                    size = leftMenuHighLightStateWidth
//                }
//            }else {
//                withAnimation {
//                    size = leftMenuNormalStateWidth
//                    leftMenuCurrentSelectIndex = -1
//                    leftMenuShowSubList = false
//                }
//            }
//        })
//        .onChange(of: mainContentfocusState, perform: { newValue in
////            if newValue ?? 0 > 6 && newValue ?? 0 > self.roomContentArray.count - 6 {
////                page += 1
////                getRoomList()
////            }
//        })
//        .simpleToast(isPresented: $showToast, options: toastOptions) {
//            Label(toastTitle, systemImage: toastTypeIsSuccess == true ? "checkmark.circle":"info.circle.fill")
//                .padding()
//                .background(toastTypeIsSuccess == true ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
//                .foregroundColor(Color.white)
//                .cornerRadius(10)
//                .padding(.top)
//
//        }
    }
    
}

