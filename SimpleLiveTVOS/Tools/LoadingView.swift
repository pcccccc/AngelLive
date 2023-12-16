//
//  LoadingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/22.
//

import SwiftUI

struct LoadingView: View {
    
    @Binding var loadingText: String
    
    var body: some View {
        VStack {
            if loadingText == "暂无内容" {
                Image(systemName: "folder.badge.questionmark")
            }else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            Text(loadingText)
                .font(.title3)
                .foregroundColor(.gray)
                .padding()
        }
    }
}

