//
//  SimpleLiveViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation

@Observable
class SimpleLiveViewModel {
    var selection = 0
    
    var danmuSettingModel = DanmuSettingModel()
    var favoriteModel = FavoriteModel()
    var favoriteLiveViewModel = LiveViewModel(roomListType: .favorite, liveType: .bilibili)
}
