//
//  LeftMenu.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/7/3.
//

import SwiftUI

struct LeftMenu: View {
    
    @Binding var size : CGFloat
    @State var leftMenuIsFocusedArray: Array<Bool> = [false, false, false, false, false]
    @State var isOpen: Bool = false
    
    var body : some View{
        VStack{
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 0, isToggleOn: $isOpen, doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                    
                }
                .frame(height: 100)
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 1, isToggleOn: $isOpen, doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })

                }
                .frame(height: 100)
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 2, isToggleOn: $isOpen, doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                  
                }
                .frame(height: 100)
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 3, isToggleOn: $isOpen, doSomething: { index, isFocused in
                        
                        self.showOrHide(index: index, isFocused: isFocused)
                    })

                }
                .frame(height: 100)
                .buttonStyle(CardButtonStyle())
            }
            
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 4, isToggleOn: $isOpen, doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })

                }
                .frame(height: 100)
                .buttonStyle(CardButtonStyle())
            }
            Spacer()
        }
        .frame(width: self.size)
        .padding(.top, 30)
        
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
                    break
                }
            }
            if flag == 0 {
                self.size = 100
                self.isOpen = false
            }
        }
    }
    
}

struct LeftMenuButton: View {
    
    @Environment(\.isFocused) private var isFocused : Bool
    var index: Int
    @Binding var isToggleOn: Bool
    var doSomething: (Int, Bool) -> Void = { _,_  in }
    
    var body: some View {
        HStack {
            Image("bilibili")
                .frame(width: 40, height: 40)
                .padding(.leading, isToggleOn ? 20 : 0)
            if isToggleOn {
                Text("英雄联盟")
//                    .padding(.trailing, 20)
                    .padding(.leading, -20)
            }
            
        }
        .frame(width: isToggleOn ? 260 : 100, height: 100)
        .onChange(of: isFocused) { newValue in
            print("index:\(index) isFocused:\(newValue)")
            self.doSomething(index, newValue)
        }
    }
}

