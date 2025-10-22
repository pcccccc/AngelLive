//
//  CloudSyncTabIcon.swift
//  AngelLive
//
//  Created by pangchong on 10/22/25.
//

import SwiftUI
import AngelLiveCore

/// iCloud同步状态的动态Tab图标
struct CloudSyncTabIcon: View {
    let syncStatus: CloudSyncStatus
    var body: some View {
        Image(systemName: iconName)
            .symbolEffect(
                .rotate.byLayer,
                options: .repeat(.periodic(delay: 0.0)),
                isActive: syncStatus == .syncing
            )
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect(.replace))
    }

    private var iconName: String {
        switch syncStatus {
        case .syncing:
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud"
        case .success:
            return "checkmark.icloud"
        case .error:
            return "exclamationmark.icloud"
        case .notLoggedIn:
            return "xmark.icloud"
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        CloudSyncTabIcon(syncStatus: .syncing)
            .font(.largeTitle)
        CloudSyncTabIcon(syncStatus: .success)
            .font(.largeTitle)
        CloudSyncTabIcon(syncStatus: .error)
            .font(.largeTitle)
        CloudSyncTabIcon(syncStatus: .notLoggedIn)
            .font(.largeTitle)
    }
}
