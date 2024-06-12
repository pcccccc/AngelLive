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
    
    @Environment(LiveViewModel.self) var liveViewModel
    @State var colors: [Color] = ColorfulPreset.winter.colors
    @State var speed = 0.5
    @Environment(\.colorScheme) var colorScheme
    @FocusState var focusState: FocusableField?

    var body : some View {
        ScrollView {
            VStack(alignment: .center) {
                Text("分类")
                    .font(.title3)
                    .bold()
                    .padding(.top, 20)
                ForEach(liveViewModel.categories.indices, id: \.self) { index in
                    MenuItem(favorite: false, icon: liveViewModel.categories[index].icon == "" ? liveViewModel.menuTitleIcon : liveViewModel.categories[index].icon, title: liveViewModel.categories[index].title, index: index, subItems: liveViewModel.categories[index].subList)
                        .frame(width: 250)
                        .padding(.top, index == 0 ? 30 : 15)
                        .padding(.bottom, index == liveViewModel.categories.count - 1 ? 50 : 15)
                        .padding([.leading, .trailing], 30)
                        .buttonStyle(.plain)
                        .background(Color.clear)
                        .focused($focusState, equals: .leftMenu(index, 0))
                }
//                if liveViewModel.showOverlay == false {
//                    if liveViewModel.selectedSubCategory.count > 0 && liveViewModel.selectedSubListIndex != -1 {
//                        if liveViewModel.selectedSubListIndex < liveViewModel.selectedSubCategory.count {
//                            HStack(spacing: 10) {
//                                if liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].icon == "" {
//                                    Image(liveViewModel.menuTitleIcon)
//                                    .resizable()
//                                    .frame(width: 30, height: 30, alignment: .leading)
//                                    .padding(.leading, -5)
//                                }else {
//                                    KFImage(URL(string: liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].icon))
//                                    .resizable()
//                                    .frame(width: 30, height: 30, alignment: .leading)
//                                    .padding(.leading, -5)
//                                }
//
//                                Text(liveViewModel.selectedSubCategory[liveViewModel.selectedSubListIndex].title)
//                                    .font(.system(size: 20))
//                                    .frame(width: 110, height: 30, alignment: .leading)
//                                    .multilineTextAlignment(.leading)
//                            }
//                            .padding(.top, 160)
//                            .padding(.leading, 5)
//                            .edgesIgnoringSafeArea(.all)
//                        }
//                    }else {
//                        HStack(spacing: 10) {
//                            Image(liveViewModel.menuTitleIcon)
//                                .resizable()
//                                .frame(width: 30, height: 30, alignment: .leading)
//                                .padding(.leading, -5)
//                            Text("直播分类")
//                                .font(.system(size: 20))
//                                .frame(width: 110, height: 30, alignment: .leading)
//                                .multilineTextAlignment(.leading)
//                        }
//                        .padding(.top, 160)
//                        .padding(.leading, 5)
//                        .edgesIgnoringSafeArea(.all)
//                    }
//                }else {
//
//                }
                
            }
            .listStyle(.plain)
        }
        .frame(minWidth: 150, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .onDisappear {
            speed = 0
        }
        .onExitCommand(perform: {
            if liveViewModel.showOverlay == true {
                liveViewModel.showOverlay = false
            }
        })
    }
}

struct MenuItem: View {
    
    @Environment(LiveViewModel.self) var liveViewModel
    @FocusState var focusState: FocusableField?
    @State var favorite: Bool
    @State var icon: String
    @State var title: String
    @State var index: Int
    @State var subItems: [LiveCategoryModel]
    
    
    var body: some View {
        VStack {
            Button(action: {
                liveViewModel.showSubCategoryList(currentCategory: liveViewModel.categories[index])
            }, label: {
                HStack(spacing: 10) {
                    Image(icon)
                        .resizable()
                        .frame(width: 30, height: 30, alignment: .leading)
                        .padding(.leading, -20)
                    Text(title)
                        .font(.system(size: 25))
                        .frame(width: 110, height: 30, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
            })
            
            if liveViewModel.selectedSubCategory.count > 0 && liveViewModel.selectedMainListCategory?.title == title  {
                ForEach(liveViewModel.selectedSubCategory.indices, id: \.self) { index in
                    if index < liveViewModel.selectedSubCategory.count {
                        SubMenuItem(favorite: favorite, icon: liveViewModel.selectedSubCategory[index].icon == "" ? liveViewModel.menuTitleIcon : liveViewModel.selectedSubCategory[index].icon, title: liveViewModel.selectedSubCategory[index].title, index: index)
                            .environment(liveViewModel)
                    }
                }
            }
        }
    }
}

struct SubMenuItem: View {
    
    @Environment(LiveViewModel.self) var liveViewModel
    @FocusState var focusState: FocusableField?
    @State var favorite: Bool
    @State var icon: String
    @State var title: String
    @State var index: Int
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button(action: {
                    liveViewModel.selectedSubListIndex = index
                    liveViewModel.roomPage = 1
                    liveViewModel.getRoomList(index: index)
                }, label: {
                    if icon == "douyin" {
                        Image(icon)
                            .resizable()
                            .frame(width: 20, height: 20, alignment: .leading)
                            .padding(.leading, -20)
                    }else {
                        KFImage(URL(string: icon))
                            .resizable()
                            .frame(width: 20, height: 20, alignment: .leading)
                            .padding(.leading, -20)
                    }
                    Text(title)
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

