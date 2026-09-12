import CloudKit
import Foundation
import Testing

@testable import AngelLiveCore

@Suite("Favorite identity rules")
struct FavoriteIdentityRulesTests {
  @Test("validIdentity trims values and rejects empty or zero sentinels")
  func validIdentityNormalization() {
    #expect(AppFavoriteModel.validIdentity("  user-1 \n") == "user-1")
    #expect(AppFavoriteModel.validIdentity("") == nil)
    #expect(AppFavoriteModel.validIdentity("   ") == nil)
    #expect(AppFavoriteModel.validIdentity("0") == nil)
    #expect(AppFavoriteModel.validIdentity(" 0 \n") == nil)
  }

  @Test("same streamer requires the same plugin source plus a valid matching user or room id")
  func sameStreamerUsesValidDimensionsOnSameSourceOnly() {
    let original = room(liveType: "source-a", userId: "u-1", roomId: "r-1")

    #expect(
      AppFavoriteModel.isSameStreamer(
        original, room(liveType: "source-a", userId: "u-1", roomId: "r-2")))
    #expect(
      AppFavoriteModel.isSameStreamer(
        original, room(liveType: "source-a", userId: "u-2", roomId: "r-1")))
    #expect(
      !AppFavoriteModel.isSameStreamer(
        original, room(liveType: "source-b", userId: "u-1", roomId: "r-1")))
    #expect(
      !AppFavoriteModel.isSameStreamer(
        room(liveType: "source-a", userId: "0", roomId: ""),
        room(liveType: "source-a", userId: "0", roomId: "")))
  }

  @Test("default unique key prefers valid room id then user id then trimmed name")
  func favoriteUniqueKeyFallbacks() {
    #expect(
      AppFavoriteModel.favoriteUniqueKey(
        for: room(liveType: "source-a", userId: "u-1", roomId: "r-1"))
        == "source-a_r_r-1")
    #expect(
      AppFavoriteModel.favoriteUniqueKey(
        for: room(liveType: "source-a", userId: "u-1", roomId: "0"))
        == "source-a_u_u-1")
    #expect(
      AppFavoriteModel.favoriteUniqueKey(
        for: room(liveType: "source-a", userName: "  Alice  ", userId: "0", roomId: ""))
        == "source-a_n_Alice")
  }

  @Test("the default room-id identity does not trigger writeback")
  func defaultRoomIdIdentityDoesNotReportChange() {
    let old = room(liveType: "source-a", userId: "old-user", roomId: "old-room")
    let refreshed = room(liveType: "source-a", userId: "new-user", roomId: "new-room")

    #expect(!AppFavoriteModel.favoriteIdentityChanged(old: old, new: refreshed))
  }

  @Test("deduplication keeps first occurrence and does not collide on invalid identities")
  func deduplicatedKeepsFirstAndIgnoresInvalidDimensions() {
    let first = room(liveType: "source-a", userName: "first", userId: "u-1", roomId: "r-1")
    let duplicateUser = room(
      liveType: "source-a", userName: "duplicate user", userId: "u-1", roomId: "r-2")
    let duplicateRoom = room(
      liveType: "source-a", userName: "duplicate room", userId: "u-2", roomId: "r-1")
    let invalidA = room(liveType: "source-a", userName: "invalid A", userId: "0", roomId: "")
    let invalidB = room(liveType: "source-a", userName: "invalid B", userId: "0", roomId: "")
    let otherSource = room(
      liveType: "source-b", userName: "other", userId: "u-1", roomId: "r-1")

    let result = AppFavoriteModel.deduplicated([
      first, duplicateUser, duplicateRoom, invalidA, invalidB, otherSource,
    ])

    #expect(result.map(\.userName) == ["first", "invalid A", "invalid B", "other"])
  }
}

@Suite("Favorite membership snapshots")
struct FavoriteMembershipSnapshotTests {
  @Test("membership controls additions removals and order while preserving refreshed payloads")
  func preservesRefreshedMembers() {
    let refreshed = room(userName: "refreshed", roomTitle: "live title", liveState: "1", userId: "u-1", roomId: "new-room")
    let removed = room(userName: "removed", userId: "u-2", roomId: "r-2")
    let stale = room(userName: "stale", liveState: "0", userId: "u-1", roomId: "old-room")
    let added = room(userName: "added", userId: "u-3", roomId: "r-3")

    let merged = AppFavoriteModel.mergingMembership([added, stale], preserving: [refreshed, removed])

    #expect(merged.map(\.userName) == ["added", "refreshed"])
    #expect(merged[1].roomTitle == "live title")
    #expect(merged[1].liveState == "1")
    #expect(merged[1].roomId == "new-room")
    #expect(AppFavoriteModel.mergingMembership([], preserving: [refreshed]).isEmpty)
    #expect(AppFavoriteModel.mergingMembership([added], preserving: []).first?.userName == "added")
  }

  @Test("conflicting user and room matches preserve the earliest current snapshot")
  func earliestMatchWinsAcrossDimensions() {
    let byRoom = room(userName: "room match", userId: "other-user", roomId: "shared-room")
    let byUser = room(userName: "user match", userId: "shared-user", roomId: "other-room")
    let member = room(userId: " shared-user \n", roomId: " shared-room ")

    #expect(AppFavoriteModel.mergingMembership([member], preserving: [byRoom, byUser]).first?.userName == "room match")
    #expect(AppFavoriteModel.mergingMembership([member], preserving: [byUser, byRoom]).first?.userName == "user match")
  }

  @Test("trimmed names only match when both snapshots have no valid identifiers")
  func anonymousNameFallback() {
    let anonymous = room(userName: "  Guest \n", roomTitle: "refreshed", userId: "0", roomId: "")
    let stale = room(userName: "Guest", userId: " ", roomId: " 0 ")
    let identified = room(userName: "Guest", roomTitle: "identified", userId: "u-1", roomId: "r-1")

    #expect(AppFavoriteModel.mergingMembership([stale], preserving: [identified, anonymous]).first?.roomTitle == "refreshed")
    #expect(AppFavoriteModel.mergingMembership([identified], preserving: [anonymous]).first?.roomTitle == "identified")
    #expect(AppFavoriteModel.mergingMembership([stale], preserving: [identified]).first?.roomTitle == stale.roomTitle)
  }

  @Test("sources and identity dimensions remain separate even when values contain separators")
  func keepsIdentityNamespacesSeparate() {
    let current = [
      room(liveType: "source-a", userName: "source a", userId: "u-1", roomId: "r-1"),
      room(liveType: "source-a|part", userName: "separator", userId: "value", roomId: "0"),
      room(liveType: "source-a", userName: "room only", userId: "0", roomId: "user-value"),
    ]
    let members = [
      room(liveType: "source-b", userName: "source b", userId: "u-1", roomId: "r-1"),
      room(liveType: "source-a", userName: "separate value", userId: "part|value", roomId: "0"),
      room(liveType: "source-a", userName: "user only", userId: "user-value", roomId: "0"),
    ]

    #expect(AppFavoriteModel.mergingMembership(members, preserving: current).map(\.userName) == members.map(\.userName))
  }

  @Test("indexed merge agrees with first-match identity rules for either primary key")
  func agreesWithReferenceMatching() {
    let values = ["", "0", " u-1 ", "u-2"]
    var current: [LiveModel] = []
    for source in ["source-a", "source-b"] {
      for userId in values {
        for roomId in values {
          current.append(room(liveType: source, userName: "name-\(current.count % 3)", roomTitle: "snapshot-\(current.count)", userId: userId, roomId: roomId))
        }
      }
    }
    let members = Array(current.reversed()) + [room(liveType: "source-c", roomId: "new-room")]
    let actual = AppFavoriteModel.mergingMembership(members, preserving: current)
    for preference in [FavoriteIdentityKey.roomId, .userId] {
      let expected = members.map { member in
        current.first {
          AppFavoriteModel.favoriteUniqueKey(for: $0, identityKey: preference)
            == AppFavoriteModel.favoriteUniqueKey(for: member, identityKey: preference)
            || AppFavoriteModel.isSameStreamer($0, member)
        } ?? member
      }
      #expect(actual.map(\.roomTitle) == expected.map(\.roomTitle))
    }
  }

  @Test("large membership batches preserve every snapshot")
  func largeMembershipBatch() {
    let current = (0..<10_000).map { index in
      room(userName: "current-\(index)", userId: "user-\(index)", roomId: "room-\(index)")
    }
    let members = current.reversed().map { item in
      room(userName: "stale", userId: item.userId, roomId: item.roomId)
    }
    let merged = AppFavoriteModel.mergingMembership(members, preserving: current)
    #expect(merged.map(\.userName) == current.reversed().map(\.userName))
  }
}

@Suite("Favorite cloud state")
struct FavoriteCloudStateTests {
  @Test("a recovered account check clears the stale cloud error")
  @MainActor
  func recoveredAccountClearsStaleError() {
    let model = AppFavoriteModel()
    model.applyCloudState(isReady: false, message: "iCloud account is temporarily not available")

    let recoveredAt = Date(timeIntervalSince1970: 1_786_291_200)
    model.applyCloudState(isReady: true, message: "正常", now: recoveredAt)

    #expect(model.cloudKitReady)
    #expect(!model.cloudReturnError)
    #expect(model.cloudKitStateString == "正常")
    #expect(model.syncStatus == .success)
    #expect(model.lastSyncTime == recoveredAt)
  }

  @Test("cloud errors only block the page when no local favorites exist")
  @MainActor
  func cloudErrorDoesNotHideLocalFavorites() {
    let model = AppFavoriteModel()
    model.applyCloudState(isReady: false, message: "iCloud account is temporarily not available")

    #expect(model.shouldShowBlockingCloudError)

    model.roomList = [room(liveType: "source-a", userId: "user-1", roomId: "room-1")]

    #expect(!model.shouldShowBlockingCloudError)
  }
}

@Suite("Favorite backup service")
struct FavoriteBackupServiceTests {
  @Test("AngelLive export decodes full LiveModel payload without item failures")
  func angelLiveRoundTripPreservesFullPayload() throws {
    let updatedAt = Date(timeIntervalSince1970: 1_790_000_000)
    let original = room(
      liveType: "fixture-live-type",
      userName: "Streamer",
      roomTitle: "Title",
      roomCover: "https://example.com/cover.jpg",
      userHeadImg: "https://example.com/avatar.jpg",
      liveState: "1",
      userId: "user-123",
      roomId: "room-456",
      identityUpdatedAt: updatedAt
    )

    let data = try FavoriteBackupService.export(
      rooms: [original], format: .angelLive, deviceName: "Unit Test Mac")
    let decoded = try FavoriteBackupService.decode(data)
    let decodedRoom = try #require(decoded.rooms.first)

    #expect(decoded.itemFailures.isEmpty)
    #expect(decoded.rooms.count == 1)
    #expect(decodedRoom == original)
    #expect(decodedRoom.identityUpdatedAt == updatedAt)
  }

  @Test("SimpleLive decode imports known plugin ids and reports unknown sites")
  func simpleLiveDecodeSeparatesKnownAndUnknownItems() throws {
    let items = [
      SimpleLiveFavoriteItem(siteId: "known-source", userName: "Known", face: "face.png", roomId: "100"),
      SimpleLiveFavoriteItem(
        siteId: "unknown-source", userName: "", face: "ignored.png", roomId: "200"),
    ]
    let data = try JSONEncoder().encode(items)

    let decoded = try FavoriteBackupService.decode(data) { siteId in
      siteId == "known-source" ? LiveType(rawValue: "fixture-live-type") : nil
    }
    let imported = try #require(decoded.rooms.first)
    let failure = try #require(decoded.itemFailures.first)

    #expect(decoded.rooms.count == 1)
    #expect(imported.liveType.rawValue == "fixture-live-type")
    #expect(imported.userName == "Known")
    #expect(imported.userHeadImg == "face.png")
    #expect(imported.roomId == "100")
    #expect(decoded.itemFailures.count == 1)
    #expect(failure.userName == "(未知主播)")
    #expect(failure.siteId == "unknown-source")
    #expect(failure.reason.contains("unknown-source"))
  }

  @Test("SimpleLive export uses the resolved plugin id")
  func simpleLiveExportUsesPluginId() throws {
    let data = try FavoriteBackupService.export(
      rooms: [room(
        liveType: "fixture-live-type",
        userName: "Known",
        userHeadImg: "face.png",
        roomId: "100"
      )],
      format: .simpleLive,
      deviceName: nil,
      siteIdForLiveType: { liveType in
        liveType.rawValue == "fixture-live-type" ? "known-source" : liveType.rawValue
      }
    )
    let items = try JSONDecoder().decode([SimpleLiveFavoriteItem].self, from: data)
    let item = try #require(items.first)

    #expect(item.siteId == "known-source")
    #expect(item.userName == "Known")
    #expect(item.face == "face.png")
    #expect(item.roomId == "100")
  }

  @Test("unrecognized backup data throws format error")
  func unrecognizedBackupThrows() {
    #expect {
      try FavoriteBackupService.decode(Data("{\"unexpected\":true}".utf8))
    } throws: { error in
      guard case FavoriteBackupError.unrecognizedFormat = error else { return false }
      return true
    }
  }

  @Test("import report exposes derived counts and failure flag")
  func importReportCounts() {
    let failure = FavoriteImportReport.Failure(
      userName: "A", siteId: "unknown-source", reason: "boom")
    let report = FavoriteImportReport(
      added: [room()], skipped: [room(roomId: "2")], failed: [failure])

    #expect(report.addedCount == 1)
    #expect(report.skippedCount == 1)
    #expect(report.failedCount == 1)
    #expect(report.hasFailures)
  }
}

@Suite("Favorite list grouping")
struct FavoriteListGroupingTests {
  @Test("live-state sorting prioritizes live then replay before offline and unknown")
  func sortedByLiveStatePrioritizesPlayableStates() {
    let offline = room(userName: "offline", liveState: "0", roomId: "offline")
    let unknown = room(userName: "unknown", liveState: "3", roomId: "unknown")
    let replay = room(userName: "replay", liveState: "2", roomId: "replay")
    let live = room(userName: "live", liveState: "1", roomId: "live")

    let result = [offline, unknown, replay, live].sortedByLiveState()

    #expect(result.map(\.userName) == ["live", "replay", "offline", "unknown"])
  }

  @Test("groupedByLiveState uses stable state titles and sort order")
  func groupedByLiveStateUsesDisplayOrder() {
    let rooms = [
      room(userName: "offline", liveState: "0", roomId: "offline"),
      room(userName: "unknown", liveState: "3", roomId: "unknown"),
      room(userName: "replay", liveState: "2", roomId: "replay"),
      room(userName: "live", liveState: "1", roomId: "live"),
    ]

    let sections = rooms.groupedBySections(style: .liveState)

    #expect(sections.map(\.title) == ["正在直播", "回放/轮播", "已下播", "未知状态"])
    #expect(sections.map(\.id) == sections.map(\.title))
  }

  @Test("append unique only filters matching source-room pairs")
  func appendUniqueUsesSourceAndRoomPair() {
    let existing = [room(liveType: "source-a", userName: "existing", roomId: "same")]
    let result = existing.appendingUnique(contentsOf: [
      room(liveType: "source-a", userName: "duplicate", roomId: "same"),
      room(liveType: "source-b", userName: "other source", roomId: "same"),
      room(liveType: "source-a", userName: "new room", roomId: "new"),
    ])

    #expect(result.map(\.userName) == ["existing", "other source", "new room"])
  }
}

@Suite("Favorite sync error display")
struct FavoriteSyncErrorDisplayTests {
  @Test("account status mapping hides synthetic negative codes")
  func accountStatusDisplayText() throws {
    let error = try #require(SyncError.from(accountStatus: .noAccount))

    #expect(error.kind == .notSignedIn)
    #expect(!error.isRetryable)
    #expect(error.displayText.contains("未登录 iCloud"))
    #expect(!error.displayText.contains("错误码 -1"))
  }

  @Test("rate limited errors expose retryAfter and are retryable")
  func ckRateLimitRetryMetadata() {
    let nsError = NSError(
      domain: CKError.errorDomain,
      code: CKError.Code.requestRateLimited.rawValue,
      userInfo: [CKErrorRetryAfterKey: 12.5]
    )
    let error = SyncError.from(CKError(_nsError: nsError))

    #expect(error.isRetryable)
    #expect(error.retryAfter == 12.5)
    #expect(error.displayText.contains("错误码"))
  }
}

private func room(
  liveType rawLiveType: String = "source-a",
  userName: String = "User",
  roomTitle: String = "Room",
  roomCover: String = "cover",
  userHeadImg: String = "avatar",
  liveState: String? = "0",
  userId: String = "user",
  roomId: String = "room",
  liveWatchedCount: String? = nil,
  identityUpdatedAt: Date? = nil
) -> LiveModel {
  LiveModel(
    userName: userName,
    roomTitle: roomTitle,
    roomCover: roomCover,
    userHeadImg: userHeadImg,
    liveType: LiveType(rawValue: rawLiveType)!,
    liveState: liveState,
    userId: userId,
    roomId: roomId,
    liveWatchedCount: liveWatchedCount,
    identityUpdatedAt: identityUpdatedAt
  )
}
