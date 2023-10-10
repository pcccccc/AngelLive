//
//  PlayView2.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/7/16.
//

import SwiftUI
import KSPlayer


struct KSAudioView: UIViewControllerRepresentable {
    
    var roomModel: LiveModel
    
    typealias UIViewControllerType = DetailViewController
    //  这里修改返回值，返回你的UIViewController，我这里是DraftsViewController
    func makeUIViewController(context: Context) -> DetailViewController {
        let draftVC = DetailViewController()
        draftVC.roomModel = roomModel
        return draftVC
    }

    func updateUIViewController(_ uiViewController: DetailViewController, context: Context) {
        
    }
}
