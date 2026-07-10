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

  @Test("same streamer requires same platform plus a valid matching user or room id")
  func sameStreamerUsesValidDimensionsOnSamePlatformOnly() {
    let original = room(liveType: "3", userId: "u-1", roomId: "r-1")

    #expect(
      AppFavoriteModel.isSameStreamer(original, room(liveType: "3", userId: "u-1", roomId: "r-2")))
    #expect(
      AppFavoriteModel.isSameStreamer(original, room(liveType: "3", userId: "u-2", roomId: "r-1")))
    #expect(
      !AppFavoriteModel.isSameStreamer(original, room(liveType: "4", userId: "u-1", roomId: "r-1")))
    #expect(
      !AppFavoriteModel.isSameStreamer(
        room(liveType: "3", userId: "0", roomId: ""), room(liveType: "3", userId: "0", roomId: "")))
  }

  @Test("default unique key prefers valid room id then user id then trimmed name")
  func favoriteUniqueKeyFallbacks() {
    #expect(
      AppFavoriteModel.favoriteUniqueKey(for: room(liveType: "3", userId: "u-1", roomId: "r-1"))
        == "3_r_r-1")
    #expect(
      AppFavoriteModel.favoriteUniqueKey(for: room(liveType: "3", userId: "u-1", roomId: "0"))
        == "3_u_u-1")
    #expect(
      AppFavoriteModel.favoriteUniqueKey(
        for: room(liveType: "3", userName: "  Alice  ", userId: "0", roomId: "")) == "3_n_Alice")
  }

  @Test("default room-id platforms do not trigger identity writeback")
  func defaultRoomIdPlatformsDoNotReportIdentityChange() {
    let old = room(liveType: "3", userId: "old-user", roomId: "old-room")
    let refreshed = room(liveType: "3", userId: "new-user", roomId: "new-room")

    #expect(!AppFavoriteModel.favoriteIdentityChanged(old: old, new: refreshed))
  }

  @Test("deduplication keeps first occurrence and does not collide on invalid identities")
  func deduplicatedKeepsFirstAndIgnoresInvalidDimensions() {
    let first = room(liveType: "3", userName: "first", userId: "u-1", roomId: "r-1")
    let duplicateUser = room(
      liveType: "3", userName: "duplicate user", userId: "u-1", roomId: "r-2")
    let duplicateRoom = room(
      liveType: "3", userName: "duplicate room", userId: "u-2", roomId: "r-1")
    let invalidA = room(liveType: "3", userName: "invalid A", userId: "0", roomId: "")
    let invalidB = room(liveType: "3", userName: "invalid B", userId: "0", roomId: "")
    let otherPlatform = room(liveType: "4", userName: "other", userId: "u-1", roomId: "r-1")

    let result = AppFavoriteModel.deduplicated([
      first, duplicateUser, duplicateRoom, invalidA, invalidB, otherPlatform,
    ])

    #expect(result.map(\.userName) == ["first", "invalid A", "invalid B", "other"])
  }
}

@Suite("Favorite backup service")
struct FavoriteBackupServiceTests {
  @Test("AngelLive export decodes full LiveModel payload without item failures")
  func angelLiveRoundTripPreservesFullPayload() throws {
    let updatedAt = Date(timeIntervalSince1970: 1_790_000_000)
    let original = room(
      liveType: "3",
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
      SimpleLiveFavoriteItem(siteId: "douyu", userName: "Known", face: "face.png", roomId: "100"),
      SimpleLiveFavoriteItem(
        siteId: "missing-platform", userName: "", face: "ignored.png", roomId: "200"),
    ]
    let data = try JSONEncoder().encode(items)

    let decoded = try FavoriteBackupService.decode(data)
    let imported = try #require(decoded.rooms.first)
    let failure = try #require(decoded.itemFailures.first)

    #expect(decoded.rooms.count == 1)
    #expect(imported.liveType.rawValue == "3")
    #expect(imported.userName == "Known")
    #expect(imported.userHeadImg == "face.png")
    #expect(imported.roomId == "100")
    #expect(decoded.itemFailures.count == 1)
    #expect(failure.userName == "(未知主播)")
    #expect(failure.siteId == "missing-platform")
    #expect(failure.reason.contains("missing-platform"))
  }

  @Test("SimpleLive export uses plugin id when a platform manifest exists")
  func simpleLiveExportUsesPluginId() throws {
    let data = try FavoriteBackupService.export(
      rooms: [room(liveType: "3", userName: "Known", userHeadImg: "face.png", roomId: "100")],
      format: .simpleLive,
      deviceName: nil
    )
    let items = try JSONDecoder().decode([SimpleLiveFavoriteItem].self, from: data)
    let item = try #require(items.first)

    #expect(item.siteId == "douyu")
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
    let failure = FavoriteImportReport.Failure(userName: "A", siteId: "3", reason: "boom")
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

  @Test("append unique only filters matching platform-room pairs")
  func appendUniqueUsesPlatformAndRoomPair() {
    let existing = [room(liveType: "3", userName: "existing", roomId: "same")]
    let result = existing.appendingUnique(contentsOf: [
      room(liveType: "3", userName: "duplicate", roomId: "same"),
      room(liveType: "4", userName: "other platform", roomId: "same"),
      room(liveType: "3", userName: "new room", roomId: "new"),
    ])

    #expect(result.map(\.userName) == ["existing", "other platform", "new room"])
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
  liveType rawLiveType: String = "3",
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
