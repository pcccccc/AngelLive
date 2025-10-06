//
//  OpenSourceListView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/3/6.
//

import SwiftUI
import AcknowList

struct OpenSourceListView: View {
    
    @State var acknowList: AcknowList = {
        let url = Bundle.main.url(forResource: "Package", withExtension: "resolved")
        let data = try? Data(contentsOf: url!)
        let acknowList = try? AcknowPackageDecoder().decode(from: data!)
        return acknowList!
    }()
    
    var body: some View {
        VStack {
            AcknowListSwiftUIView(acknowList: acknowList)
        }
    }
}

#Preview {
    OpenSourceListView()
}
