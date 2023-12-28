//
//  LeftMenu.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/7/3.
//

import SwiftUI
import Kingfisher
import GameController
import LiveParse
import ColorfulX

struct LeftMenu: View {
    
    @EnvironmentObject var liveViewModel: LiveStore
    @State var colors: [Color] = ColorfulPreset.winter.colors
    @State var speed = 0.5
    @Environment(\.colorScheme) var colorScheme
    @FocusState var focusState: FocusableField?

    var body : some View {
        ScrollView {
            VStack(alignment: .center) {
                if liveViewModel.showOverlay == false {
                    if liveViewModel.selectedSubCategory.count > 0 {
                        HStack(spacing: 10) {
                            if liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].icon == "" {
                                Image(liveViewModel.menuTitleIcon)
                                .resizable()
                                .frame(width: 30, height: 30, alignment: .leading)
                                .padding(.leading, -5)
                            }else {
                                KFImage(URL(string: liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].icon))
                                .resizable()
                                .frame(width: 30, height: 30, alignment: .leading)
                                .padding(.leading, -5)
                            }
                                
                                
                            Text(liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].title)
                                .font(.system(size: 20))
                                .frame(width: 110, height: 30, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.top, 10)
                        .padding(.leading, 5)
                        .edgesIgnoringSafeArea(.all)
                    }else {
                        HStack(spacing: 10) {
                            Image(liveViewModel.menuTitleIcon)
                                .resizable()
                                .frame(width: 30, height: 30, alignment: .leading)
                                .padding(.leading, -5)
                            Text("英雄联盟")
                                .font(.system(size: 20))
                                .frame(width: 110, height: 30, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.top, 10)
                        .padding(.leading, 5)
                        .edgesIgnoringSafeArea(.all)
                    }
                }else {
                    ForEach(liveViewModel.categories.indices, id: \.self) { index in
                        VStack {
                            Button(action: {
                                liveViewModel.showSubCategoryList(currentCategory: liveViewModel.categories[index])
                            }, label: {
                                HStack(spacing: 10) {
                                    Image(liveViewModel.categories[index].icon == "" ? liveViewModel.menuTitleIcon : liveViewModel.categories[index].icon)
                                        .resizable()
                                        .frame(width: 30, height: 30, alignment: .leading)
                                        .padding(.leading, -20)
                                    Text(liveViewModel.categories[index].title)
                                        .font(.system(size: 25))
                                        .frame(width: 110, height: 30, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                }
                            })
                            .frame(width: 250)
                            .padding(.top, index == 0 ? 50 : 15)
                            .padding(.bottom, index == liveViewModel.categories.count - 1 ? 50 : 15)
                            .padding([.leading, .trailing], 30)
                            .buttonStyle(.plain)
                            .background(Color.clear)
                            .focused($focusState, equals: .leftMenu(index))
                            .contextMenu(menuItems: {
                                Button(action: {
                                    Task {
    //                                    await favoriteAction()
                                    }
                                }, label: {
                                    HStack {
                                        Image(systemName: "heart.fill")
                                        Text("收藏频道")
                                    }
                                })
                            })
                            if liveViewModel.selectedMainListCategory?.title == liveViewModel.categories[index].title {
                                ForEach((liveViewModel.selectedSubCategory).indices, id: \.self) { index in
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Button(action: {
                                                liveViewModel.selectedSubListIndex = index
                                                liveViewModel.roomPage = 1
//                                                liveViewModel.getRoomList(index: index)
                                            }, label: {
                                                KFImage(URL(string: liveViewModel.selectedSubCategory[index].icon == "" ? liveViewModel.menuTitleIcon : liveViewModel.selectedSubCategory[index].icon))
                                                    .resizable()
                                                    .frame(width: 20, height: 20, alignment: .leading)
                                                    .padding(.leading, -20)
                                                Text(liveViewModel.selectedSubCategory[index].title)
                                                    .font(.system(size: 20))
                                                    .frame(width: 110, height: 20, alignment: .leading)
                                                    .multilineTextAlignment(.leading)
                                                    .padding(.leading, -50)
                                            })
                                            .frame(width: 200, height: 30)
                                            .padding([.top, .bottom], 15)
                                            .padding(.leading, 50)
                                            .padding(.trailing, 30)
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
            }
            .listStyle(.plain)
            
        }
        .frame(minWidth: 150 ,maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
        .background(ColorfulView(colors: $colors, speedFactor: $speed))
        .onAppear {
            colors = colorScheme == .dark ? [Color.init(hex: 0xAAAAAA, alpha: 1), Color.init(hex: 0x353937, alpha: 1), Color.init(hex: 0xAAAAAA, alpha: 1), Color.init(hex: 0x353937, alpha: 1)] : ColorfulPreset.winter.colors
        }
        .onChange(of: liveViewModel.showOverlay) { value in
            if liveViewModel.showOverlay == true {
                focusState = .leftMenu(0)
            }
        }
    }
}

#Preview {
    LeftMenu()
        .environmentObject(LiveStore(liveType: .bilibili))
}
