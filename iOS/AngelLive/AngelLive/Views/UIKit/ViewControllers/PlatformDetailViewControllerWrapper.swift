//
//  PlatformDetailViewControllerWrapper.swift
//  AngelLive
//
//  Created by pangchong on 10/21/25.
//

import SwiftUI
import AngelLiveCore

struct PlatformDetailViewControllerWrapper: UIViewControllerRepresentable {
    @Environment(PlatformDetailViewModel.self) var viewModel

    func makeUIViewController(context: Context) -> PlatformDetailViewController {
        return PlatformDetailViewController(viewModel: viewModel)
    }

    func updateUIViewController(_ uiViewController: PlatformDetailViewController, context: Context) {
        // 根据需要更新 UI
    }
}
