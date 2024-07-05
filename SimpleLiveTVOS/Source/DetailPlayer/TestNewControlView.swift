//
//  TestNewControlView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/15.
//

import SwiftUI
import Shimmer


struct TestPlayerControlView: View {

    @FocusState var state: PlayControlFocusableField?
    @State var lastOptionState: PlayControlFocusableField?
    @State var showTop = false
    @State var onceTips = false
    @State var showControl = false {
        didSet {
            if showControl == true {
                startTimer()
            }
        }
    }
    @State var showTips = false {
        didSet {
            if showTips == true {
                startTipsTimer()
                onceTips = true
            }
        }
    }
    @State private var controlViewOptionSecond = 5
    @State private var tipOptionSecond = 3
    @State private var contolTimer: Timer? = nil
    @State private var tipsTimer: Timer? = nil
    
    let topGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.1)]),
        startPoint: .top,
        endPoint: .bottom
    )
    let bottomGradient = LinearGradient(
        gradient: Gradient(colors: [Color.black.opacity(0.1), Color.black.opacity(0.5)]),
        startPoint: .top,
        endPoint: .bottom
    )
    
    var body: some View {
        ZStack {
            if showTop {
                VStack(spacing: 20) {
                    HStack {
                        Button("收藏") {
                            
                        }
                        Button("历史") {
                            
                        }
                        Button("分区") {
                            
                        }
                    }
                    .buttonStyle(.plain)
                    .focusSection()
                    
                    ScrollView(.horizontal) {
                        LazyHGrid(rows: [GridItem(.fixed(192))], content: {
                            ForEach(0..<10) { i in
                                Button {
                                    
                                } label: {
                                    Image("1")
                                        .resizable()
                                }
                                .frame(width: 320, height: 192)
                                .buttonStyle(.borderless)
                                .focused($state, equals: .listContent(i))
                            }
                        })
                    }
                    
                    .frame(height: 192)
                    .padding([.leading, .trailing], 55)
                    .scrollClipDisabled()
                    .focusSection()
                    
                    Spacer()
                }
                .frame(width: 1920)
                .buttonStyle(.plain)
                .transition(.move(edge: .top))
                .onExitCommand(perform: {
                    withAnimation {
                        showTop = false
                    }
                    state = lastOptionState
                })
            }else {
                VStack {
                    HStack {
                        Spacer()
                        VStack {
                            Image(systemName: "chevron.compact.down")
                                .foregroundStyle(.gray)
                            Text("下滑切换直播间")
                                .foregroundStyle(.gray)
                        }
                        .shimmering(active: true)
                        Spacer()
                    }
                    Spacer()
                }
                .opacity(showTips ? 1 : 0)
                .opacity(1)
                VStack() {
                    ZStack {
                        HStack {
                            Text("testtesttest")
                                .font(.title3)
                                .padding(.leading, 15)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .background {
                            Rectangle()
                                .fill(topGradient)
                                .shadow(radius: 10)
                                .frame(height: 150)
                        }
                        .frame(height: 150)
                    }
                    
                    
                    Spacer()
                    HStack(alignment: .center, spacing: 15) {
                        
                            Button(action: {}, label: {
                                
                            })
                            .padding(.leading, -80)
                            .clipShape(.circle)
                            .frame(width: 40, height: 40)
                            .focused($state, equals: .left)
                            
                        VStack {
                            Button(action: {
                                
                            }, label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                            })
                            .contextMenu(menuItems: {
                                Button("debug mode") {
            //                        roomInfoViewModel.toggleTimer()
                                }
                            })
                            .focused($state, equals: .playPause)
                            .clipShape(.circle)
                            .padding(.leading, -20)
                            
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                        VStack {
                            Button(action: {
                                
                            }, label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundColor(.white)
                                    .font(.system(size: 30, weight: .bold))
                                    .frame(width: 40, height: 40)
                            })
                            .clipShape(.circle)
                            .padding(.leading, -20)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                      
                        VStack {
                            Button(action: {
                               
                            }, label: {
                                Image(systemName:   "heart")
                                    .foregroundColor(.white)
                                    .font(.system(size: 30, weight: .bold))
                                    .frame(width: 40, height: 40)
                                    .padding(.top, 3)
                                    .contentTransition(.symbolEffect(.replace))
                            })
                            .clipShape(.circle)
                            .padding(.leading, -20)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                       
                        Color.green
                            .cornerRadius(10)
                            .frame(width: 20, height: 20)
                        Text("Live")
                            .foregroundStyle(.white)
                        Spacer()
                        VStack {
                            Menu {
                                
                            } label: {
                                Text("testtest")
                                    .font(.system(size: 30, weight: .bold))
                                    .frame(height: 50, alignment: .center)
                                    .padding(.top, 10)
                                    .foregroundStyle(.white)
                            }
                            .frame(height: 60)
                            .clipShape(.capsule)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                        
                        VStack {
                            Button(action: {
                                
                            }, label: {
                                Image("icon-danmu-close-focus")
                                    .resizable()
                                    .frame(width: 40, height: 40)
                            })
                            .focused($state, equals: .danmu)
                            .clipShape(.circle)
                            
                            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                                Text("")
                                    .frame(width: 40)
                            })
                            .focused($state, equals: .list)
                            .opacity(0)
                        }
                        .padding(.top, 60)
                        
                        Button(action: {}, label: {
                            
                        })
                        .padding(.trailing, -80)
                        .clipShape(.circle)
                        .frame(width: 40, height: 40)
                        .focused($state, equals: .right)
                    }
                    .background {
                        Rectangle()
                            .fill(bottomGradient)
                            .shadow(radius: 10)
                            .frame(height: 150)
                    }
                    .frame(height: 150)
                }
                .transition(.opacity)
                .opacity(showControl ? 1 : 0)
                .onExitCommand {
                    if showControl == true {
                        showControl.toggle()
                    }
                }
            }
        }
        .onAppear {
            state = .playPause
            showControl = true
        }
        .onChange(of: state, { oldValue, newValue in
            
            if showControl == false {
                showControl.toggle()
            }
            
            if oldValue != .list && isListContentField(oldValue) == false && oldValue != nil {
                lastOptionState = oldValue
            }
            print(lastOptionState)
            print(state)
            
            if newValue == .left {
                state = .danmu
            }else if newValue == .right {
                state = .playPause
            }else if newValue == .list {
                withAnimation {
                    showTop = true
                    state = .listContent(0)
                }
            }
            
        })
        
        .onMoveCommand(perform: { direction in
            print(direction)
        })
        
    }
    
    func startTimer() {
        contolTimer?.invalidate() // 停止之前的计时器
        controlViewOptionSecond = 5  // 重置计时器

        contolTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if controlViewOptionSecond > 0 {
                controlViewOptionSecond -= 1
            } else {
                withAnimation {
                    showControl = false
                    if onceTips == false {
                        showTips = true
                    }
                }
                contolTimer?.invalidate() // 计时器停止
            }
        }
    }
    
    func startTipsTimer() {
        
        if onceTips {
            return
        }
        
        tipsTimer?.invalidate() // 停止之前的计时器
        tipOptionSecond = 3 // 重置计时器

        tipsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if tipOptionSecond > 0 {
                tipOptionSecond -= 1
            } else {
                withAnimation {
                    showTips = false
                }
                tipsTimer?.invalidate() // 计时器停止
            }
        }
    }
    
    func isListContentField(_ field: PlayControlFocusableField?) -> Bool {
        if case .listContent(_) = field {
            return true
        }
        return false
    }
    
    func favoriteAction() {
//        if favoriteModel.roomList.contains(where: { roomInfoViewModel.currentRoom == $0 }) == false {
//            Task {
//                try await favoriteModel.addFavorite(room: roomInfoViewModel.currentRoom)
//                roomInfoViewModel.showToast(true, title: "收藏成功")
//            }
//        }else {
//            Task {
//                try await  favoriteModel.removeFavoriteRoom(room: roomInfoViewModel.currentRoom)
//                roomInfoViewModel.showToast(true, title: "取消收藏成功")
//            }
//        }
    }
}

#Preview {
    TestPlayerControlView()
        .edgesIgnoringSafeArea(.all)
}
