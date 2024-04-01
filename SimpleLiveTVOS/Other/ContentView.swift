//
//  ContentView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2023/6/26.
//

import SwiftUI
import Kingfisher
import GameController
import LiveParse
import Network
import UDPBroadcast
import Foundation
import Darwin

struct ContentView: View {
    
    @State private var selection = 1
    @StateObject var favoriteStore = FavoriteStore()
    @State var broadcastConnection: UDPBroadcastConnection?
    
    var body: some View {
        NavigationView {
            TabView(selection:$selection) {
                FavoriteMainView()
                    .tabItem {
                        if favoriteStore.isLoading == true || favoriteStore.cloudKitReady == false {
                            Label(
                                title: {  },
                                icon: {
                                    Image(systemName: favoriteStore.isLoading == true ? "arrow.triangle.2.circlepath.icloud" : favoriteStore.cloudKitReady == true ? "checkmark.icloud" : "exclamationmark.icloud" )
                                                          
                                }
                            )
                            .contentTransition(.symbolEffect(.replace))
                        }else {
                            Text("收藏")
                        }
                    }
                .tag(0)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .bilibili)
                    .tabItem {
                        Text("B站")
                    }
                .tag(1)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .huya)
                    .tabItem {
                        Text("虎牙")
                    }
                .tag(2)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .douyu)
                    .tabItem {
                        Text("斗鱼")
                    }
                .tag(3)
                .environmentObject(favoriteStore)
                ListMainView(liveType: .douyin)
                    .tabItem {
                        Text("抖音")
                    }
                .tag(4)
                .environmentObject(favoriteStore)
                SearchRoomView()
                    .tabItem {
                        Text("搜索")
                    }
                .tag(5)
                .environmentObject(favoriteStore)
                SettingView()
                    .tabItem {
                        Text("设置")
                    }
                .tag(6)
                .environmentObject(favoriteStore)
            }
        }
        .onAppear {
            do {
                
            }
            Task {
                try await Douyin.getRequestHeaders()
                
                let port = 23235
                let backlog = 10
                let bufferSize = 4096

                // 创建服务器端套接字
                let serverSocket = socket(AF_INET, SOCK_STREAM, 0)
                guard serverSocket != -1 else {
                    print("Error creating server socket")
                    exit(-1)
                }

                // 绑定服务器套接字到指定端口
                var serverAddress = sockaddr_in()
                serverAddress.sin_family = sa_family_t(AF_INET)
                serverAddress.sin_addr.s_addr = INADDR_ANY.bigEndian
                serverAddress.sin_port = in_port_t(Int16(port).bigEndian)

                let bindResult = bind(serverSocket, UnsafePointer<sockaddr>(&serverAddress), socklen_t(MemoryLayout<sockaddr_in>.size))
                guard bindResult != -1 else {
                    print("Error binding server socket to port")
                    exit(-1)
                }

                // 监听客户端连接请求
                listen(serverSocket, Int32(backlog))

                while true {
                    // 接受客户端连接
                    var clientAddress = sockaddr()
                    var clientAddressLength = socklen_t(MemoryLayout<sockaddr>.size)
                    let clientSocket = accept(serverSocket, &clientAddress, &clientAddressLength)
                    guard clientSocket != -1 else {
                        print("Error accepting client connection")
                        continue
                    }
                    
                    // 处理客户端请求
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                    let bytesRead = recv(clientSocket, buffer, bufferSize, 0)
                    let request = String(cString: buffer)
                    print("Received request: \(request)")
                    
                    // 发送响应数据到客户端
                    let response = "Hello, client!"
                    let bytesSent = send(clientSocket, response, response.count, 0)
                    print("Sent response: \(response)")
                    
                    // 关闭客户端套接字
                    close(clientSocket)
                    buffer.deallocate()
                }

                
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


