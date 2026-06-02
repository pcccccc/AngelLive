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
        if #available(iOS 18.0, *) {
            Image(systemName: iconName)
                .symbolEffect(
                    .rotate.byLayer,
                    options: .repeat(.periodic(delay: 0.5)),
                    isActive: syncStatus == .syncing
                )
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        } else {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var iconName: String {
        switch syncStatus {
        case .syncing:
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill"
        case .success:
            return "checkmark.icloud.fill"
        case .error:
            return "exclamationmark.icloud.fill"
        case .notLoggedIn:
            return "xmark.icloud.fill"
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
