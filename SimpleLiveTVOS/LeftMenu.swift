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
    
    var body : some View{
        VStack{
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 0 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 1 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 2 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 3 ,doSomething: { index, isFocused in
                        
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
                .buttonStyle(CardButtonStyle())
            }
            
            HStack{
                Button(action: {
                    
                }) {
                    LeftMenuButton(index: 4 ,doSomething: { index, isFocused in
                        self.showOrHide(index: index, isFocused: isFocused)
                    })
                }
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
            for itemFocused in self.leftMenuIsFocusedArray {
                if itemFocused == true {
                    self.size = 300
                    flag = 1
                    break
                }
            }
            if flag == 0 {
                self.size = 100
            }
        }
    }
    
}

struct LeftMenuButton: View {
    
    @Environment(\.isFocused) private var isFocused : Bool
    var index: Int
    var doSomething: (Int, Bool) -> Void = { _,_  in }
    
    var body: some View {
        HStack {
            Image("bilibili")
                .frame(width: 30, height: 30)
            if isFocused {
                Text(isFocused ? "英雄联盟2": "英雄联盟")
            }
        }
        .onChange(of: isFocused) { newValue in
            
            self.doSomething(index, newValue)
        }
    }
}

