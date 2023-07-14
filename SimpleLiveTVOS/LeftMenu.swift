//
//  LeftMenu.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/7/3.
//

import SwiftUI
import Kingfisher

struct LeftMenu: View {
    
    @Binding var size : CGFloat
    @State var leftMenuIsFocusedArray: Array<Bool> = []
    @State var leftSubMenuIsFocusedArray: Array<Bool> = []
    @State var isOpen: Bool = false
    @State var isSubOpen: Bool = false
    @State private var isShowSubList = false
    @State private var mainList = [BilibiliMainListModel]()
    @State private var currentIndex = -1
    
    
    var body : some View {
       
        List(mainList.indices, id: \.self, rowContent: { index in
            Section {

                Button(action: {
                    isShowSubList.toggle()
                    currentIndex = index
                    leftSubMenuIsFocusedArray.removeAll()
                    for _ in mainList[currentIndex].list ?? [] {
                        leftSubMenuIsFocusedArray.append(false)
                    }
                }, label: {
                    LeftMenuButton(index: 0, isToggleOn: $isOpen, title: mainList[index].name, doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })

                })
                .frame(height: 100)
                .listRowInsets(EdgeInsets(top: 15, leading: isOpen ? 35 : 15, bottom: 15, trailing: 15))
                .buttonStyle(CardButtonStyle())
                if currentIndex == index && isShowSubList {
                    ForEach((mainList[index].list ?? []).indices, id: \.self) { subIndex in
                        Button(action: {}, label: {
                            LeftMenuSubItem(index: subIndex, image: (mainList[index].list ?? [])[subIndex].pic, name: (mainList[index].list ?? [])[subIndex].name, doSomething: { subListCurrentFocusIndex, isFocused in
                                self.leftSubMenuIsFocusedArray[subListCurrentFocusIndex] = isFocused
                                var flag = 0
                                for itemFocused in self.leftSubMenuIsFocusedArray {
                                    if itemFocused == true {
                                        flag = 1
                                        self.isShowSubList = true
                                        self.isOpen = true
                                        self.isSubOpen = true
                                        break
                                    }
                                }
                                if flag == 0 {
//                                    self.isShowSubList = false
                                    self.isOpen = false
                                    self.isSubOpen = false
                                }
                            })
//
                        })
                        .buttonStyle(CardButtonStyle())
                        .frame(height: 50)
                    }
                }
            }
        })
        .onAppear {
            Task {
                self.mainList = try await Bilibili.getBiliBiliList().data ?? []
                for _ in self.mainList {
                    leftMenuIsFocusedArray.append(false)
                }
            }
        }
        .frame(width: (isOpen || isSubOpen) ? 300 : 130)
        .padding(.top, 30)
//        .background(Color.red)
        
    }
    
    
    func showOrHide(index: Int ,isFocused: Bool) {
        
        withAnimation {
            self.leftMenuIsFocusedArray[index] = isFocused
            var flag = 0
            print(self.leftMenuIsFocusedArray)
            for itemFocused in self.leftMenuIsFocusedArray {
                if itemFocused == true {
                    self.size = 300
                    flag = 1
                    self.isOpen = true
                    if self.isShowSubList == true {
                        self.isSubOpen = true
                    }
                    break
                }
            }
            if flag == 0 {
                self.size = 130
                if self.isShowSubList == true {
                    self.isOpen = true
                    self.isSubOpen = true
                }else {
                    self.isOpen = false
                    self.isSubOpen = false
                    self.isShowSubList = false
                }
            }
            
            print("isOpen:\(isOpen)")
            print("isSubOpen:\(isSubOpen)")
            print("isShowSubList:\(isShowSubList)")
            print("currentIndex:\(currentIndex)")
        }
    }
    
}

struct LeftMenuButton: View {
    
    @Environment(\.isFocused) private var isFocused : Bool
    var index: Int
    @Binding var isToggleOn: Bool
    var title: String
    var doSomething: (Int, Bool) -> Void = { _,_  in }
    
    
    var body: some View {
        HStack {
            Image("bilibili")
                .frame(width: 40, height: 40)
            if isToggleOn {
                Text(title)
//                    .padding(.trailing, 20)
                    .padding(.leading, -25)
            }
        }
        .frame(width: isToggleOn ? 230 : 100, height: 100)
        .onChange(of: isFocused) { newValue in
            print("index:\(index) isFocused:\(newValue)")
            self.doSomething(index, newValue)
        }

    }
}

struct LeftMenuSubItem: View {
    @Environment(\.isFocused) private var isFocused : Bool
    var index: Int
    var image: String
    var name: String
    var doSomething: (Int, Bool) -> Void = { _,_  in }
 
    var body: some View {
        HStack {
            KFImage(URL(string: image))
                .resizable()
                .frame(width: 30, height: 30)
                .padding(.leading, 20)

            Text(name)
                .font(.system(size: 22))
                .padding(.trailing, 20)
                .padding(.leading, -20)
        }
        .onChange(of: isFocused) { newValue in
            self.doSomething(index, newValue)
        }
    }
        
}

