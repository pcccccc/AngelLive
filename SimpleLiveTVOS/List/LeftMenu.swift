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
    
    @EnvironmentObject var liveListViewModel: LiveListViewModel
    @State var colors: [Color] = ColorfulPreset.winter.colors
    @State var speed = 0.5
    @Environment(\.colorScheme) var colorScheme
    @FocusState var focusState: FocusableField?

    var body : some View {
        ScrollView {
            VStack(alignment: .center) {
                ForEach(liveListViewModel.categories.indices, id: \.self) { index in
                    VStack {
                        Button(action: {
                            liveListViewModel.showSubCategoryList(currentCategory: liveListViewModel.categories[index])
                        }, label: {
                            HStack(spacing: 10) {
                                Image(liveListViewModel.categories[index].icon == "" ? liveListViewModel.menuTitleIcon : liveListViewModel.categories[index].icon)
                                    .resizable()
                                    .frame(width: 30, height: 30, alignment: .leading)
                                    .padding(.leading, -20)
                                Text(liveListViewModel.categories[index].title)
                                    .font(.system(size: 25))
                                    .frame(width: 110, height: 30, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }
                        })
                        .frame(width: 250)
                        .padding(.top, index == 0 ? 50 : 15)
                        .padding(.bottom, index == liveListViewModel.categories.count - 1 ? 50 : 15)
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
                        if liveListViewModel.selectedMainListCategory?.title == liveListViewModel.categories[index].title {
                            ForEach((liveListViewModel.selectedSubCategory).indices, id: \.self) { index in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Button(action: {
                                            liveListViewModel.getRoomList(index: index)
                                        }, label: {
                                            KFImage(URL(string: liveListViewModel.selectedSubCategory[index].icon == "" ? liveListViewModel.menuTitleIcon : liveListViewModel.selectedSubCategory[index].icon))
                                                .resizable()
                                                .frame(width: 20, height: 20, alignment: .leading)
                                                .padding(.leading, -20)
                                            Text(liveListViewModel.selectedSubCategory[index].title)
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
            .listStyle(.plain)
            
        }
        .frame(maxWidth: 300, maxHeight: .infinity)
        .background(ColorfulView(colors: $colors, speedFactor: $speed))
        .cornerRadius(10)
        .padding([.top, .bottom], 50)
        .padding(.leading, 10)
        .onAppear {
            colors = colorScheme == .dark ? [Color.init(hex: 0x1A1E1C, alpha: 1), Color.init(hex: 0x1A1E1C, alpha: 1), Color.init(hex: 0x353937, alpha: 1)] : ColorfulPreset.winter.colors
        }
        
    }
}

#Preview {
    LeftMenu()
        .environmentObject(LiveListViewModel(liveType: .bilibili))
}
