//
//  SimpleLiveViewModel.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/6/14.
//

import Foundation
import Observation
import SimpleToast

@Observable
class SimpleLiveViewModel {
    var selection = 0
    let favoriteModel = FavoriteModel()
    let danmuSettingModel = DanmuSettingModel()
    
    var showToast: Bool = false
    var toastTitle: String = ""
    var toastTypeIsSuccess: Bool = false
    var toastOptions = SimpleToastOptions(
        alignment: .topLeading, hideAfter: 1.5
    )
    
    //MARK: 操作相关
    
    func showToast(_ success: Bool, title: String) {
        self.showToast = true
        self.toastTitle = title
        self.toastTypeIsSuccess = success
    }

}
