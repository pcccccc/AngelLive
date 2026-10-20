//
//  HistoryListView.swift
//  SimpleLiveTVOS
//
//  Created by pc on 2024/1/10.
//

import SwiftUI
import AngelLiveCore
import AngelLiveDependencies

enum HistoryFocusField: Hashable {
    case clearButton
    case card(Int)
}

struct HistoryListView: View {
    let appViewModel: AppState

    var body: some View {
        if appViewModel.pluginAvailability.hasAvailablePlugins {
            TVFullUIHistoryListView(appViewModel: appViewModel)
        } else {
            LegacyHistoryListView(appViewModel: appViewModel)
        }
    }
}

private struct LegacyHistoryListView: View {

    var appViewModel: AppState
    @FocusState var focusState: HistoryFocusField?
    var liveViewModel: LiveViewModel?
    @State private var showClearAlert = false

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
        self.liveViewModel = LiveViewModel(roomListType: .history, liveType: .placeholder, appViewModel: appViewModel)
    }

    var body: some View {
        VStack {
            HStack {
                Text("历史记录")
                    .font(.title2)

                Spacer()

                if !appViewModel.historyViewModel.watchList.isEmpty {
                    Button(action: { showClearAlert = true }) {
                        Label("清空全部", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    .focused($focusState, equals: .clearButton)
                }
            }
            .padding(.horizontal, 50)
            .focusSection()

            if appViewModel.historyViewModel.watchList.isEmpty {
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    Text("暂无历史记录")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("观看直播后将自动记录在这里")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.fixed(380), spacing: 50),
                            GridItem(.fixed(380), spacing: 50),
                            GridItem(.fixed(380), spacing: 50),
                            GridItem(.fixed(380), spacing: 50)
                        ],
                        alignment: .center,
                        spacing: 50
                    ) {
                        ForEach(appViewModel.historyViewModel.watchList.indices, id: \.self) { index in
                            LiveCardView(index: index)
                                .environment(liveViewModel)
                                .environment(appViewModel)
                                .frame(width: 370, height: 280)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .safeAreaPadding(.top, 30)
                    .focusSection()
                }
            }
        }
        .task {
            for index in 0 ..< (liveViewModel?.roomList ?? []).count {
                liveViewModel?.getLastestHistoryRoomInfo(index)
            }
        }
        .onPlayPauseCommand(perform: {
        })
        .alert("清空历史记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive) {
                appViewModel.historyViewModel.clearAll()
            }
        } message: {
            Text("确定要清空所有观看记录吗？此操作不可恢复。")
        }
    }
}


private enum TVHistoryKind: String, CaseIterable, Identifiable {
    case live = "直播"
    case shortDrama = "短剧"

    var id: Self { self }
}

private enum TVHistoryHeaderFocus: Hashable {
    case kind(TVHistoryKind)
    case clear
}

private struct TVHistoryRefreshIdentity: Equatable {
    let kind: TVHistoryKind
    let roomIDs: [String]
}

private struct TVHistoryPendingRemoval {
    enum Record {
        case live(LiveModel)
        case shortDrama(ShortDramaHistoryEntry)
    }

    let focusID: String
    let record: Record
}

/// FullUI keeps the original history grid and card geometry; only the source changes.
private struct TVFullUIHistoryListView: View {
    let appViewModel: AppState
    @State private var liveViewModel: LiveViewModel
    @State private var progressStore = ShortDramaProgressStore.shared
    @State private var selectedKind: TVHistoryKind = .live
    @State private var showClearAlert = false
    @State private var feedbackMessage: String?
    @State private var playingDrama: LiveModel?
    @State private var playedDramaKey: ShortDramaProgressKey?
    @State private var pendingHistoryRemoval: TVHistoryPendingRemoval?
    @FocusState private var headerFocus: TVHistoryHeaderFocus?
    @FocusState private var cardFocus: FocusableField?

    init(appViewModel: AppState) {
        self.appViewModel = appViewModel
        _liveViewModel = State(initialValue: LiveViewModel(
            roomListType: .history, liveType: .placeholder,
            appViewModel: appViewModel, shouldLoadData: false
        ))
    }

    private var liveRooms: [LiveModel] {
        appViewModel.historyViewModel.watchList.filter { !progressStore.isShortDramaHistory($0) }
    }

    private var recordCount: Int {
        selectedKind == .live ? liveRooms.count : progressStore.historyEntries.count
    }

    private var historyFocusIDs: [String] {
        selectedKind == .live
            ? liveRooms.map { liveFocusID($0.id) }
            : progressStore.historyEntries.map { dramaFocusID($0.id) }
    }

    private func liveFocusID(_ roomID: String) -> String {
        "live:\(roomID)"
    }

    private func dramaFocusID(_ key: ShortDramaProgressKey) -> String {
        "drama:\(key.pluginID.utf8.count):\(key.pluginID)\(key.roomID.utf8.count):\(key.roomID)"
    }

    var body: some View {
        VStack {
            header
            typeSwitcher

            if recordCount == 0 {
                emptyState
            } else {
                historyGrid
            }
        }
        .environment(liveViewModel)
        .environment(appViewModel)
        .defaultFocus($headerFocus, .kind(selectedKind))
        .onAppear {
            progressStore.loadHistory(legacyRooms: appViewModel.historyViewModel.watchList)
        }
        .onChange(of: appViewModel.historyViewModel.watchList) { _, rooms in
            progressStore.loadHistory(legacyRooms: rooms)
        }
        .task(id: TVHistoryRefreshIdentity(kind: selectedKind, roomIDs: liveRooms.map(\.id))) {
            await liveViewModel.refreshFullUIHistoryRooms(selectedKind == .live ? liveRooms : [])
        }
        .onChange(of: progressStore.historyWarning, initial: true) { _, warning in
            if let warning { feedbackMessage = warning }
        }
        .onChange(of: cardFocus) { oldFocus, newFocus in
            Logger.debug(
                "History menu focus changed: hadCard=\(oldFocus != nil) hasCard=\(newFocus != nil) pending=\(pendingHistoryRemoval != nil)",
                category: .ui
            )
            guard let pending = pendingHistoryRemoval,
                  newFocus == .historyContent(pending.focusID),
                  oldFocus != newFocus else { return }
            finishPendingHistoryRemoval()
        }
        .onDisappear {
            pendingHistoryRemoval = nil
        }
        .onPlayPauseCommand { }
        .alert("清空\(selectedKind.rawValue)历史记录", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清空", role: .destructive, action: clearSelectedHistory)
        } message: {
            Text(selectedKind == .shortDrama
                 ? "确定要清空短剧观看记录吗？已保存的逐集播放进度会保留。"
                 : "确定要清空直播观看记录吗？短剧观看记录会保留。")
        }
        .alert("提示", isPresented: Binding(
            get: { feedbackMessage != nil },
            set: { if !$0 { feedbackMessage = nil } }
        )) {
            Button("好", role: .cancel) { feedbackMessage = nil }
        } message: {
            Text(feedbackMessage ?? "")
        }
        .fullScreenCover(item: $playingDrama, onDismiss: restoreDramaFocus) { room in
            TVShortDramaPlayerView(room: room) { playingDrama = nil }
                .id(room.id)
        }
    }

    private var header: some View {
        HStack {
            Text("历史记录")
                .font(.title2)
            Spacer()
            if recordCount > 0 {
                Button { showClearAlert = true } label: {
                    Label("清空\(selectedKind.rawValue)", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .focused($headerFocus, equals: .clear)
            }
        }
        .padding(.horizontal, 50)
        .focusSection()
    }

    private var typeSwitcher: some View {
        HStack(spacing: 30) {
            ForEach(TVHistoryKind.allCases) { kind in
                Button {
                    selectedKind = kind
                    liveViewModel.currentRoom = nil
                    cardFocus = nil
                    headerFocus = .kind(kind)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: kind == .live ? "tv" : "film")
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text(kind.rawValue)
                            .fontWeight(selectedKind == kind ? .semibold : .regular)
                    }
                    .font(.caption)
                    .foregroundStyle(.primary)
                }
                .focused($headerFocus, equals: .kind(kind))
                .accessibilityLabel(kind.rawValue + "历史记录")
                .accessibilityAddTraits(selectedKind == kind ? .isSelected : [])
                .onMoveCommand { direction in
                    guard direction == .down, let firstID = historyFocusIDs.first else { return }
                    headerFocus = nil
                    cardFocus = .historyContent(firstID)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 20)
        .focusSection()
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("暂无\(selectedKind.rawValue)观看记录")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("观看\(selectedKind.rawValue)后将自动记录在这里")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var historyGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(380), spacing: 50), count: 4),
                alignment: .center, spacing: 50
            ) {
                if selectedKind == .live {
                    ForEach(Array(liveRooms.enumerated()), id: \.element.id) { index, savedRoom in
                        let room = liveViewModel.roomList.first { $0.id == savedRoom.id } ?? savedRoom
                        LiveCardView(
                            index: index,
                            externalFocusState: $cardFocus,
                            onMoveCommand: { moveFromCard($0, id: liveFocusID(savedRoom.id)) },
                            currentLiveModel: room,
                            historyDeletion: {
                                requestHistoryRemoval(.live(room), id: liveFocusID(savedRoom.id))
                            },
                            historyFocusID: liveFocusID(savedRoom.id)
                        )
                        .frame(width: 370, height: 280)
                    }
                } else {
                    ForEach(Array(progressStore.historyEntries.enumerated()), id: \.element.id) { index, entry in
                        LiveCardView(
                            index: index,
                            externalFocusState: $cardFocus,
                            onMoveCommand: { moveFromCard($0, id: dramaFocusID(entry.id)) },
                            currentLiveModel: dramaCardRoom(entry),
                            historySelection: { openDrama(entry) },
                            historyDeletion: {
                                requestHistoryRemoval(.shortDrama(entry), id: dramaFocusID(entry.id))
                            },
                            historyFocusID: dramaFocusID(entry.id)
                        )
                        .frame(width: 370, height: 280)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .safeAreaPadding(.top, 30)
            .focusSection()
        }
    }

    private func dramaCardRoom(_ entry: ShortDramaHistoryEntry) -> LiveModel {
        let episode = entry.episodeNumber.map { "第\($0)集" } ?? entry.episodeTitle ?? "继续观看"
        let minutes = String(format: "%.0f", floor(entry.position / 60))
        let seconds = String(format: "%02.0f", floor(entry.position.truncatingRemainder(dividingBy: 60)))
        let progress = entry.completed ? "已看完" : "\(minutes):\(seconds)"
        let subtitle = entry.room == nil ? "插件不可用" : "\(episode) · \(progress)"
        return LiveModel(
            userName: entry.title, roomTitle: subtitle, roomCover: entry.coverURL ?? "",
            userHeadImg: entry.room?.userHeadImg ?? "", liveType: entry.room?.liveType ?? .placeholder,
            liveState: nil, userId: entry.room?.userId ?? "", roomId: entry.key.roomID,
            liveWatchedCount: nil
        )
    }

    private func openDrama(_ entry: ShortDramaHistoryEntry) {
        guard let room = entry.room else {
            feedbackMessage = "此短剧的插件当前不可用。重新安装对应插件后可继续观看，播放进度会保留。"
            return
        }
        playedDramaKey = entry.key
        playingDrama = room
    }

    private func restoreDramaFocus() {
        if let key = playedDramaKey,
           let entry = progressStore.historyEntries.first(where: { $0.key == key }) {
            headerFocus = nil
            cardFocus = .historyContent(dramaFocusID(entry.id))
        } else {
            focusSelectedKind()
        }
        playedDramaKey = nil
    }

    private func moveFromCard(_ direction: MoveCommandDirection, id: String) {
        guard let index = historyFocusIDs.firstIndex(of: id) else { return }
        if direction == .up, index < 4 { focusSelectedKind() }
    }

    private func focusSelectedKind() {
        cardFocus = nil
        headerFocus = .kind(selectedKind)
    }

    private func restoreFocusAfterRemoval(index: Int) {
        let remainingIDs = historyFocusIDs
        if remainingIDs.isEmpty {
            focusSelectedKind()
        } else {
            headerFocus = nil
            cardFocus = .historyContent(remainingIDs[min(index, remainingIDs.count - 1)])
        }
    }

    private func requestHistoryRemoval(_ record: TVHistoryPendingRemoval.Record, id: String) {
        // Keep the source alive until tvOS returns focus after the menu closes.
        // Menu content can stay cached, so its onDisappear is not a dismissal signal.
        // Only a new focus change after this request can commit the deletion.
        pendingHistoryRemoval = TVHistoryPendingRemoval(focusID: id, record: record)
        Logger.debug(
            "History menu deletion requested: sourceFocused=\(cardFocus == .historyContent(id))",
            category: .ui
        )
    }

    private func finishPendingHistoryRemoval() {
        guard let pending = pendingHistoryRemoval,
              cardFocus == .historyContent(pending.focusID) else { return }
        pendingHistoryRemoval = nil
        Logger.debug("History menu deletion committed after focus returned", category: .ui)
        switch pending.record {
        case .live(let room):
            removeLiveHistory(room)
        case .shortDrama(let entry):
            removeDramaHistory(entry)
        }
    }

    private func removeLiveHistory(_ room: LiveModel) {
        guard let index = historyFocusIDs.firstIndex(of: liveFocusID(room.id)) else { return }
        appViewModel.historyViewModel.removeHistories(ids: [room.id])
        restoreFocusAfterRemoval(index: index)
    }

    private func removeDramaHistory(_ entry: ShortDramaHistoryEntry) {
        guard let index = historyFocusIDs.firstIndex(of: dramaFocusID(entry.id)) else { return }
        do {
            try progressStore.removeHistory(for: entry.key)
            restoreFocusAfterRemoval(index: index)
        } catch {
            feedbackMessage = "删除观看记录失败：\(error.localizedDescription)"
        }
    }

    private func clearSelectedHistory() {
        do {
            if selectedKind == .shortDrama {
                try progressStore.clearHistory()
            } else {
                appViewModel.historyViewModel.removeHistories(ids: Set(liveRooms.map(\.id)))
            }
            focusSelectedKind()
        } catch {
            feedbackMessage = "清空观看记录失败：\(error.localizedDescription)"
        }
    }
}
