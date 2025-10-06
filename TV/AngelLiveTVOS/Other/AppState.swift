//
//  AppState.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation

@Observable
class AppState {
    var selection = 0
    var favoriteViewModel = AppFavoriteModel()
    var danmuSettingsViewModel = DanmuSettingModel()
    var searchViewModel = SearchViewModel()
    var historyViewModel = HistoryModel()
    var playerSettingsViewModel = PlayerSettingModel()
    var generalSettingsViewModel = GeneralSettingModel()
}
