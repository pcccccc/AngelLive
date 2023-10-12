//
//  PlayerView.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/7/16.
//

import SwiftUI
import AVKit

struct PlayerView: View {
    
    @State private var willBeginFullScreenPresentation: Bool = false
    @State private var player = AVPlayer()
    @State private var url = ""
    var roomModel: LiveModel
    var liveType: LiveType

    
    var body: some View {
        
        VStack {
            VideoPlayer(player: player)
                .edgesIgnoringSafeArea(.all)
                .onAppear() {
                    Task {
                        if liveType == .bilibili {
                            let quality = try await Bilibili.getVideoQualites(roomModel:roomModel)
                            if quality.code == 0 {
                                if let qualityDescription = quality.data.quality_description {
                                    var maxQn = 0
                                    for item in qualityDescription {
                                        if item.qn > maxQn {
                                            maxQn = item.qn
                                        }
                                    }
                                    let playInfo = try await Bilibili.getPlayUrl(roomModel: roomModel, qn: maxQn)
                                    for streamInfo in playInfo.data.playurl_info.playurl.stream {
                                        if streamInfo.protocol_name == "http_hls" {
                                            url = (streamInfo.format.last?.codec.last?.url_info.last?.host ?? "") + (streamInfo.format.last?.codec.last?.base_url ?? "") + (streamInfo.format.last?.codec.last?.url_info.last?.extra ?? "")
                                            let item = AVPlayerItem(asset: AVURLAsset(url: URL(string: url)!))
                                            player = AVPlayer(playerItem: item)
                                            player.play()
                                            break
                                        }
                                    }
                                }
                            }
                        }else if liveType == .douyin {
                            let liveData = try await Douyin.getDouyinRoomDetail(streamerData: roomModel)
                            if liveData.data?.data?.count ?? 0 > 0 {
                                let FULL_HD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.FULL_HD1 ?? ""
                                let HD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.HD1 ?? ""
                                let SD1 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.SD1 ?? ""
                                let SD2 = liveData.data?.data?.first?.stream_url?.hls_pull_url_map.SD2 ?? ""
                                if FULL_HD1.count > 0 {
                                    url = FULL_HD1
                                }else if HD1.count > 0 {
                                    url = HD1
                                }else if SD1.count > 0 {
                                    url = SD1
                                }else if SD2.count > 0 {
                                    url = SD2
                                }else {
                                    url = ""
                                }
                                let item = AVPlayerItem(asset: AVURLAsset(url: URL(string: url)!))
                                player = AVPlayer(playerItem: item)
                                player.play()
                            }
                        }else if liveType == .douyu {
                            let liveData = try await Douyu.getPlayArgs(rid: roomModel.roomId)
                            if liveData.error != -1 {
                                print("\(liveData.data?.rtmp_url ?? "")")
                                print("\(liveData.data?.rtmp_live ?? "")")
//                                let item = AVPlayerItem(asset: AVURLAsset(url: URL(string: "\(liveData.data?.rtmp_url ?? "")/\(liveData.data?.rtmp_live ?? "")")!))
//                                
//                                player = AVPlayer(playerItem: item)
//                                player.play()
//                                print(player.error)
                            }
                        }else if liveType == .huya {
                            let liveData = try await Huya.getPlayArgs(rid: roomModel.roomId)
                            if liveData != nil {
                                let streamInfo = liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value.first
                                var playQualitiesInfo: Dictionary<String, String> = [:]
                                if let urlComponent = URLComponents(string: "?\(streamInfo?.sFlvAntiCode ?? "")") {
                                    if let queryItems = urlComponent.queryItems {
                                        for item in queryItems {
                                            playQualitiesInfo.updateValue(item.value ?? "", forKey: item.name)
                                        }
                                    }
                                }
                                playQualitiesInfo.updateValue("1", forKey: "ver")
                                playQualitiesInfo.updateValue("2110211124", forKey: "sv")
                                let uid = try await Huya.getAnonymousUid()
                                let now = Date().timeIntervalSince1970 * 1000
                                playQualitiesInfo.updateValue("\((Int(uid) ?? 0) + Int(now))", forKey: "seqid")
                                playQualitiesInfo.updateValue(uid, forKey: "uid")
                                playQualitiesInfo.updateValue(Huya.getUUID(), forKey: "uuid")
                                let ss = "\(playQualitiesInfo["seqid"] ?? "")|\(playQualitiesInfo["ctype"] ?? "")|\(playQualitiesInfo["t"] ?? "")".md5
                                let base64EncodedData = (playQualitiesInfo["fm"] ?? "").data(using: .utf8)!
                                if let data = Data(base64Encoded: base64EncodedData) {
                                    let fm = String(data: data, encoding: .utf8)!
                                    var nsFM = fm as NSString
                                    nsFM = nsFM.replacingOccurrences(of: "$0", with: uid).replacingOccurrences(of: "$1", with: streamInfo?.sStreamName ?? "").replacingOccurrences(of: "$2", with: ss).replacingOccurrences(of: "$3", with: playQualitiesInfo["wsTime"] ?? "") as NSString
                                    playQualitiesInfo.updateValue((nsFM as String).md5, forKey: "wsSecret")
                                    playQualitiesInfo.removeValue(forKey: "fm")
                                    var playInfo: Array<URLQueryItem> = []
                                    for key in playQualitiesInfo.keys {
                                        let value = playQualitiesInfo[key] ?? ""
                                        playInfo.append(URLQueryItem(name: key, value: value))
                                    }
                                    var urlComps = URLComponents(string: "")!
                                    urlComps.queryItems = playInfo
                                    let result = urlComps.url!
                                    var res = result.absoluteString as NSString
                                    for streamInfo in liveData?.roomInfo.tLiveInfo.tLiveStreamInfo.vStreamInfo.value ?? [] {
                                        print("\(streamInfo.sFlvUrl)/\(streamInfo.sStreamName).\(streamInfo.sFlvUrlSuffix)\(res)")
                                        print("\(streamInfo.sHlsUrl)/\(streamInfo.sStreamName).\(streamInfo.sHlsUrlSuffix)\(res)")
                                        url = "\(streamInfo.sHlsUrl)/\(streamInfo.sStreamName).\(streamInfo.sHlsUrlSuffix)\(res)"
                                        let item = AVPlayerItem(asset: AVURLAsset(url: URL(string: url)!))
                                        player = AVPlayer(playerItem: item)
                                        player.play()
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }
}

//struct PlayerView_Previews: PreviewProvider {
//    static var previews: some View {
//        PlayerView()
//    }
//}
