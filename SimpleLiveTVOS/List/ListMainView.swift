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
    
    init(liveType: LiveType) {
        self.liveType = liveType
        self._liveListViewModel = StateObject(wrappedValue: LiveListViewModel(liveType: liveType))
    }
    
    var body: some View {
        ZStack {
            VStack {
                Button("1") {
                    liveListViewModel.showOverlay.toggle()
                }
                Button("2") {
                    
                }
                Button("3") {
                    
                }
            }
            .frame(width: 1920, height: 1080)
        }.overlay {
            
            HStack {
                LeftMenu()
                    .offset(x: liveListViewModel.leftListOverlay)
                    .animation(.spring(duration: 1.0), value: liveListViewModel.leftListOverlay)
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
                Spacer()
            }
            .background(liveListViewModel.showOverlay == true ? Color.black.opacity(0.5) : Color.clear)
            .edgesIgnoringSafeArea(.all)
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

