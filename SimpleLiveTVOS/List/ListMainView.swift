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

  
    @State var needFullScreenLoading: Bool = false
    private static let topId = "topIdHere"
    
    var liveType: LiveType
    @StateObject var liveViewModel: LiveStore
    @FocusState var focusState: FocusableField?
    
    init(liveType: LiveType) {
        self.liveType = liveType
        self._liveViewModel = StateObject(wrappedValue: LiveStore(roomListType: .live, liveType: liveType))
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                ZStack {
                }
                .id(Self.topId)
                LazyVGrid(columns: [GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380)), GridItem(.fixed(380))], spacing: 60) {
                    ForEach(liveViewModel.roomList.indices, id: \.self) { index in
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
                        .frame(width: 370, height: 240)
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
                                        .onExitCommand {
                                            switch focusState {
                                                case .leftMenu(_):
                                                    liveViewModel.showOverlay = false
                                                    focusState = .mainContent(liveViewModel.selectedRoomListIndex)
                                                case .mainContent(_):
                                                    break
                                                case .none:
                                                    break
                                            }
                                        }
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
        .simpleToast(isPresented: $liveViewModel.showToast, options: liveViewModel.toastOptions) {
            Label(liveViewModel.toastTitle, systemImage: liveViewModel.toastImage)
//                .symbolEffect(.appear.down.wholeSymbol)
                .padding()
                .background(Color.red.opacity(0.8))
                .foregroundColor(Color.white)
                .cornerRadius(10)
                .padding(.top)
            }
    }
    
}

