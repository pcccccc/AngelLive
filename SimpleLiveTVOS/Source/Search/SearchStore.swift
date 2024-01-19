//
//  SearchStore.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/12.
//

import Foundation
import LiveParse
import SimpleToast

class SearchStore: ObservableObject {
    
    @Published var searchTypeArray = ["关键词", "链接/分享口令/房间号"]
    @Published var searchTypeIndex = 0
    @Published var page = 0
    @Published var showToast: Bool = false
    @Published var toastTitle: String = ""
    @Published var toastTypeIsSuccess: Bool = false
    @Published var toastImage: String = "checkmark.circle" {
        didSet {
            toastImage = toastTypeIsSuccess == true ? "checkmark.circle" : "xmark.circle"
        }
    }
    @Published var toastOptions = SimpleToastOptions (
        hideAfter: 1.5
    )
    @Published var searchText: String = ""
}
