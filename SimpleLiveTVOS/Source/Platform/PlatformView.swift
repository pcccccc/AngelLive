//
//  PlatformView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/11.
//

import SwiftUI
import LiveParse

struct PlatformView: View {
    @State var data = [LiveParsePlatformInfo]()
    let column = Array(repeating: GridItem(.flexible(minimum: 120, maximum: .infinity)), count: 3)
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: column, alignment: .leading, spacing: 5) {
                ForEach(data.indices, id: \.self) { index in
                    Color.red
                        .transition(.moveAndOpacity)
                        .frame(width: 300, height: 150)
                }
            }
        }
        .onAppear {
            data.removeAll()
            let allPlatform = LiveParseTools.getAllSupportPlatform()
            for index in 0 ..< allPlatform.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(0.05 * Double(index))) {
                    withAnimation(.bouncy(duration: 0.25)) {
                        self.data.append(allPlatform[index])
                    }
                }
            }
        }
    }
}

extension AnyTransition {
    static var moveAndOpacity: AnyTransition {
        AnyTransition.opacity
    }
}

#Preview {
    PlatformView()
}
