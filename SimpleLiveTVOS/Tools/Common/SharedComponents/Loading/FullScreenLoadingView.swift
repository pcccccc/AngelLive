//
//  FullScreenLoadingView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/4/3.
//

import SwiftUI

struct FullScreenLoadingView: View {
    
    @Binding var loadingText: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                Text(loadingText)
            }
        }
    }
}

#Preview {
    FullScreenLoadingView(loadingText: .constant("TEST"))
        .frame(width: 1920, height: 1080)
}

