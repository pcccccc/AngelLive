//
//  SearchView.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import SwiftUI
import AngelLiveCore
import LiveParse
import Kingfisher

struct SearchView: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @State private var searchText = ""

    var body: some View {
        ContentUnavailableView(
            "搜索功能",
            systemImage: "magnifyingglass",
            description: Text("搜索功能开发中，敬请期待")
        )
        .navigationTitle("搜索")
        .searchable(text: $searchText, prompt: "搜索直播间或主播")
    }
}

#Preview {
    SearchView()
        .environment(SearchViewModel())
}
