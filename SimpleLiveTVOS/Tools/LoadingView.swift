//
//  LoadingView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/22.
//

import SwiftUI
import Shimmer

struct LoadingView: View {
    
    var body: some View {
        VStack {
            Image("placeholder")
                .resizable()
                .frame(height: 210)
                .cornerRadius(5)
            HStack(spacing: 15) {
                Image("placeholder")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(20)
                    .shimmering(active: true)
                VStack (alignment: .leading, spacing: 5) {
                    Text("loading....")
                        .font(.system(size: 22))
                        .shimmering(active: true)
                    Text("loading....")
                        .font(.system(size: 16))
                        .shimmering(active: true)
                }
                Spacer()
            }
            .frame(height: 50)
        }
    }
}

