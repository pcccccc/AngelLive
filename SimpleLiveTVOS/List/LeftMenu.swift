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
                            Text("直播分类")
                                .font(.system(size: 20))
                                .frame(width: 110, height: 30, alignment: .leading)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.top, 160)
                        .padding(.leading, 5)
                        .edgesIgnoringSafeArea(.all)
                    }
                }else {
                    if liveViewModel.currentLiveTypeFavoriteCategoryList.isEmpty == false {
                        Text("收藏")
                            .padding(.top, liveViewModel.currentLiveTypeFavoriteCategoryList.count < 2 ? 60 : 50)
                            .background(Color.red)
                        ForEach(liveViewModel.currentLiveTypeFavoriteCategoryList.indices, id: \.self) { index in
                            MenuItem(favorite: true, icon: liveViewModel.currentLiveTypeFavoriteCategoryList[index].icon == "" ? liveViewModel.menuTitleIcon : liveViewModel.currentLiveTypeFavoriteCategoryList[index].icon, title: liveViewModel.currentLiveTypeFavoriteCategoryList[index].title, index: index, subItems: liveViewModel.currentLiveTypeFavoriteCategoryList[index].subList)
                                .frame(width: 250)
                                .padding(.top, index == 0 ? 50 : 15)
                                .padding(.bottom, index == liveViewModel.currentLiveTypeFavoriteCategoryList.count - 1 ? 50 : 15)
                                .padding([.leading, .trailing], 30)
                                .buttonStyle(.plain)
                                .background(Color.clear)
                                .focused($focusState, equals: .leftFavorite(index, 0))
                                .contextMenu(menuItems: {
                                    Button(action: {
                                        liveViewModel.addFavoriteCategory(liveViewModel.categories[index])
                                    }, label: {
                                        HStack {
                                            Image(systemName: "heart.fill")
                                            Text("收藏分类")
                                        }
                                    })
                                })
                            
                        }
                        .background(Color.red)
                        Text("全部")
                    }
                    ForEach(liveViewModel.categories.indices, id: \.self) { index in
                        MenuItem(favorite: false, icon: liveViewModel.categories[index].icon == "" ? liveViewModel.menuTitleIcon : liveViewModel.categories[index].icon, title: liveViewModel.categories[index].title, index: index, subItems: liveViewModel.categories[index].subList)
                            .frame(width: 250)
                            .padding(.top, index == 0 ? 50 : 15)
                            .padding(.bottom, index == liveViewModel.categories.count - 1 ? 50 : 15)
                            .padding([.leading, .trailing], 30)
                            .buttonStyle(.plain)
                            .background(Color.clear)
                            .focused($focusState, equals: .leftMenu(index, 0))
                            .contextMenu(menuItems: {
                                Button(action: {
                                    liveViewModel.addFavoriteCategory(liveViewModel.categories[index])
                                }, label: {
                                    HStack {
                                        Image(systemName: "heart.fill")
                                        Text("收藏分类")
                                    }
                                })
                            })
                    }
                }
                
            }
            .listStyle(.plain)
            
        }
        .frame(minWidth: 150, maxWidth: .infinity, minHeight: 30, maxHeight: .infinity)
        .background(ColorfulView(colors: $colors, speedFactor: $speed))
        .onAppear {
            colors = colorScheme == .dark ? [Color.init(hex: 0xAAAAAA, alpha: 1), Color.init(hex: 0x353937, alpha: 1), Color.init(hex: 0xAAAAAA, alpha: 1), Color.init(hex: 0x353937, alpha: 1)] : ColorfulPreset.winter.colors
        }
    }
}

struct MenuItem: View {
    
    @EnvironmentObject var liveViewModel: LiveStore
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
                    SubMenuItem(favorite: favorite, icon: liveViewModel.selectedSubCategory[index].icon == "" ? liveViewModel.menuTitleIcon : liveViewModel.selectedSubCategory[index].icon, title: liveViewModel.selectedSubCategory[index].title, index: index)
                }
            }
        }
    }
}

struct SubMenuItem: View {
    
    @EnvironmentObject var liveViewModel: LiveStore
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
                    KFImage(URL(string: icon))
                        .resizable()
                        .frame(width: 20, height: 20, alignment: .leading)
                        .padding(.leading, -20)
                    Text(title)
                        .font(.system(size: 20))
                        .frame(width: 110, height: 20, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, -50)
                })
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
                .frame(width: 200, height: 30)
                .padding([.top, .bottom], 15)
                .padding(.leading, 50)
                .padding(.trailing, 30)
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    LeftMenu()
        .environmentObject(LiveStore(roomListType: .live, liveType: .bilibili))
}
