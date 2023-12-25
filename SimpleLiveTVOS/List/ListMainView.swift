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
    @StateObject var liveListViewModel: LiveListStore
    @FocusState var focusState: FocusableField?
    
    init(liveType: LiveType) {
        self.liveType = liveType
        self._liveListViewModel = StateObject(wrappedValue: LiveListStore(liveType: liveType))
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                ZStack {
                }
                .id(Self.topId)
                LazyVGrid(columns: [GridItem(.fixed(400)), GridItem(.fixed(400)), GridItem(.fixed(400)), GridItem(.fixed(400))], spacing: 70) {
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
                VStack(alignment: .leading, spacing: 50) {
                    HStack(alignment: .top) {
                        ZStack {
                            VStack(alignment: .leading) {
                                HStack {
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
                                        .animation(.easeInOut(duration: 0.25), value: liveListViewModel.showOverlay)
                                        .edgesIgnoringSafeArea(.all)
                                        .frame(width: liveListViewModel.leftWidth, height: liveListViewModel.leftHeight)
                                        .cornerRadius(liveListViewModel.leftMenuCornerRadius)
                                        
                                    Spacer(minLength: 0)
                                }
                                .frame(width: 300, height: liveListViewModel.leftHeight)
                                Spacer(minLength: 0)
                                
                            }
                            .frame(width: liveListViewModel.showOverlay == true ? 150: 300, height: liveListViewModel.showOverlay == true ? 50: 700)
                        }
                        .frame(width: 300, height: 700)
                        Spacer()
                    }
                    Spacer()
                }
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: 1,y: 1)
            }
            
        }
        
    }
    
}

