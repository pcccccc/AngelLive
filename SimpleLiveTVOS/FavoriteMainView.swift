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
                    LiveCardView(liveModel: $roomContentArray[index], mainContentfocusState: _mainContentfocusState, index: index, isFavoritePage: true) { success, delete, hint in
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
        .task {
            await getRoomList()
        }
    }
    
    func getRoomList() async {
        do {
            let newItem = try await CloudSQLManager.searchRecord()
            for item in newItem {
                if roomContentArray.contains(where: { $0.roomId == item.roomId }) == false {
                    roomContentArray.append(item)
                }
            }
        }catch {
            
            
        }
    }
}

#Preview {
    FavoriteMainView()
}
