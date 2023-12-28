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
    @StateObject var liveViewModel: LiveStore
    @FocusState var focusState: FocusableField?
    
    init(liveType: LiveType) {
        self.liveType = liveType
        self._liveViewModel = StateObject(wrappedValue: LiveStore(liveType: liveType))
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                ZStack {
                }
                .id(Self.topId)
                LazyVGrid(columns: [GridItem(.fixed(400)), GridItem(.fixed(400)), GridItem(.fixed(400)), GridItem(.fixed(400))], spacing: 70) {
                    ForEach(liveViewModel.roomList.indices, id: \.self) { index in
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
                            .environmentObject(liveViewModel)
                            .onMoveCommand(perform: { direction in
                                switch direction {
//                                case .right:
//                                    liveViewModel.showOverlay = false
                                case .left:
//                                    liveViewModel.showOverlay = true
                                    if index % 4 == 0 {
                                        liveViewModel.showOverlay = true
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
                                        .environmentObject(liveViewModel)
                                        .onMoveCommand(perform: { direction in
                                            switch direction {
                                            case .right:
                                                liveViewModel.showOverlay = false
                                            case .left:
                                                liveViewModel.showOverlay = true
                                            default:
                                                print(222)
                                            }
                                        })
                                        .animation(.easeInOut(duration: 0.25), value: liveViewModel.showOverlay)
                                        .edgesIgnoringSafeArea(.all)
                                        .frame(width: liveViewModel.leftWidth, height: liveViewModel.leftHeight)
                                        .cornerRadius(liveViewModel.leftMenuCornerRadius)
                                        
                                    Spacer(minLength: 0)
                                }
                                .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftHeight)
                                Spacer(minLength: 0)
                                
                            }
                            .frame(width: liveViewModel.showOverlay == true ? 150: 300, height: liveViewModel.showOverlay == true ? liveViewModel.leftMenuMinHeight:  liveViewModel.leftMenuMaxHeight)
                        }
                        .frame(width: liveViewModel.leftMenuMaxWidth, height: liveViewModel.leftMenuMaxHeight)
                        Spacer()
                    }
                    Spacer()
                }
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: 1,y: 30)
            }
            
        }
        
    }
    
}

