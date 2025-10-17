//
//  PlayerControlCardViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/8/23.
//

import Foundation
import Observation
import AngelLiveDependencies

@Observable
final class PlayerControlCardViewModel {
    var liveModel: LiveModel
    var cardIndex: Int
    var selectIndex: Int
    var liveStateLoading = false
    
    init(liveModel: LiveModel, cardIndex: Int, selectIndex: Int) {
        self.liveModel = liveModel
        self.cardIndex = cardIndex
        self.selectIndex = selectIndex
    }
}
