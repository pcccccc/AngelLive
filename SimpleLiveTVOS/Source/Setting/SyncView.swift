//
//  SyncView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2024/4/1.
//

import SwiftUI

struct SyncView: View {
    
    
    // 使用示例
    let udpServer = UDPServer(port: 23235)

    
    var body: some View {
        Text("Hello, World!")
            .onAppear {
                
            }
    }
}

#Preview {
    SyncView()
}
