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
    var favoriteModel: LiveViewModel?
    var appFavoriteModel = AppFavoriteModel()
    var danmuSettingModel = DanmuSettingModel()
    var searchModel = SearchViewModel()
    var historyModel = HistoryModel()
    var playerSettingModel = PlayerSettingModel()
    var generalSettingModel = GeneralSettingModel()
}
