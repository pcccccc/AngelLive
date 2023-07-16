//
//  LeftMenu.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/7/3.
//

import SwiftUI
import Kingfisher

struct LeftMenu: View {
    
    @Binding var size: CGFloat
    @Binding var currentIndex: Int
    @Binding var isShowSubList: Bool
    @State private var mainList = [BilibiliMainListModel]()
    var leftMenuDidClick: (Int, Int, BilibiliCategoryModel) -> Void = { _,_,_   in }

    var body : some View {
       
        List(mainList.indices, id: \.self, rowContent: { index in
            Section {
                Button(action: {
                    currentIndex = index
                    isShowSubList.toggle()
                }, label: {
                    HStack {
                        Image("bilibili")
                            .frame(width: 40, height: 40)
                        if size == leftMenuHighLightStateWidth {
                            Text(mainList[index].name)
                                .padding(.leading, -25)
                        }
                    }
                    .frame(width: size - 40 ,height: 100)
                })
                .buttonStyle(CardButtonStyle())
                if currentIndex == index && isShowSubList {
                    ForEach((mainList[index].list ?? []).indices, id: \.self) { subIndex in
                        Button(action: {
                            getCategoryRooms(subIndex: subIndex)
                        }, label: {
                            HStack {
                                KFImage(URL(string: (mainList[index].list ?? [])[subIndex].pic))
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                    .padding(.leading, 20)

                                Text((mainList[index].list ?? [])[subIndex].name)
                                    .font(.system(size: 22))
                                    .padding(.trailing, 20)
                                    .padding(.leading, -40)
                            }
                            .frame(width: size - 30 - 70, height: 50)
                        })
                        .buttonStyle(CardButtonStyle())
                
                        .padding(.leading, 30)
                    }
                }
            }
        })
        .onAppear {
            Task {
                self.mainList = try await Bilibili.getBiliBiliList().data ?? []
            }
        }
        .frame(width: size)
        .padding(.top, 30)
    }
    
    func getCategoryRooms(subIndex: Int) {
        let category = self.mainList[currentIndex].list?[subIndex]
        self.leftMenuDidClick(currentIndex, subIndex, category!)
    }
}

