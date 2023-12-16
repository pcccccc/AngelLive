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

struct LeftMenu: View {
    
    @EnvironmentObject var liveListViewModel: LiveListViewModel

    var body : some View {
        ScrollView {
            VStack(alignment: .center) {
                ForEach(liveListViewModel.categories.indices, id: \.self) { index in
                    Button(action: {
                        //                    currentIndex = index
                        //                    isShowSubList.toggle()
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
                    .padding([.top, .bottom], 15)
                    .padding([.leading, .trailing], 30)
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
        }
        .frame(maxWidth: 300, maxHeight: .infinity)
    }
}

