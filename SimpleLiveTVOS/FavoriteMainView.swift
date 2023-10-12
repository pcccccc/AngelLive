//
//  FavoriteMainView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/11.
//

import SwiftUI
import Kingfisher
import SimpleToast

struct FavoriteMainView: View {
    
    @FocusState var mainContentfocusState: Int?
    @State private var roomContentArray: Array<LiveModel> = []
    @State private var page = 1
    @State var showToast: Bool = false
    @State var toastTitle: String = ""
    @State var toastTypeIsSuccess: Bool = false
    private let toastOptions = SimpleToastOptions(
        hideAfter: 1
    )
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 35) {
                ForEach(roomContentArray.indices, id: \.self) { index in
                    LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, isFavorite: true) { success, delete, hint in
                        toastTypeIsSuccess = success
                        toastTitle = hint
                        showToast.toggle()
                        if delete {
                            roomContentArray.remove(at: index)
                        }
                    }
                }
            }
        }
        .onChange(of: mainContentfocusState, perform: { newValue in
            if newValue ?? 0 > 6 && newValue ?? 0 > self.roomContentArray.count - 6 {
                page += 1
                getRoomList()
            }
        })
        .onAppear {
            page = 1
            getRoomList()
        }
    }
    
    func getRoomList() {
        if page == 1 {
            roomContentArray.removeAll()
        }
        roomContentArray += SQLiteManager.manager.search(page: page)
    }
}

#Preview {
    FavoriteMainView()
}
