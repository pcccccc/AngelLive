//
//  AppFavoriteModel+Identity.swift
//  AngelLiveCore
//
//  收藏「身份/去重」的单一 SSOT:多维度识别同一主播、稳定主键(recordName)、多维度去重。
//  从 AppFavoriteModel 主文件抽出(纯搬迁,调用点不变),集中承载领域规则。
//

import Foundation

extension AppFavoriteModel {
    /// 规整一个标识字段:非空、非 "0"、去空白后才算「有效维度」,否则返回 nil。
    static func validIdentity(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (t.isEmpty || t == "0") ? nil : t
    }

    /// 多维度判断是否同一主播(平台无关)。同平台下,userId 或 roomId 任一**有效维度**
    /// 相同即视为同一主播。这样不依赖平台适配也能罩住脏数据:
    /// - userId 时有时无(空/0)的平台靠 roomId 命中;
    /// - roomId 每场直播会变的平台靠 userId 命中。
    static func isSameStreamer(_ a: LiveModel, _ b: LiveModel) -> Bool {
        guard a.liveType.rawValue == b.liveType.rawValue else { return false }
        if let au = validIdentity(a.userId), let bu = validIdentity(b.userId), au == bu { return true }
        if let ar = validIdentity(a.roomId), let br = validIdentity(b.roomId), ar == br { return true }
        return false
    }

    /// 刷新后判断是否发生**值得回写**的身份变化。身份回写**只服务于声明了
    /// `favoriteIdentityKey: userId` 的平台**(roomId 每场会变、userId 稳定)。
    ///
    /// 默认 `roomId` 身份平台一律返回 false,**不自动回写**,原因:
    /// 1. roomId 即主键且通常稳定,无需回写;
    /// 2. roomId 的"变化"无法区分「真换房」与「占位漂移」——部分平台(如主播未直播时)
    ///    `getRoomDetail` 会返回**共享占位 roomId + userId=0**,多个主播漂到同一占位值。
    ///    若据此回写会把不同主播 re-key 到同一 recordName → CloudKit 碰撞、互相覆盖
    ///    (实测 "record to insert already exists" / Server Record Changed 14/2004)。
    /// 这正是设计 §2.3/§8 的危险组合;这类平台要么 roomId 稳定(无需回写),要么应在
    /// manifest 声明 `preserveFavoriteRoomInfoOnRefresh` 保留原房间信息。
    ///
    /// 也故意**不**把昵称/标题/封面/头像纳入触发条件:高频快照若当触发器会导致几乎每次
    /// 刷新都全量回写 → 写放大(§3 R3)。快照仍随记录上云(makeRecord 写全字段),只是不单独触发。
    static func favoriteIdentityChanged(old: LiveModel, new: LiveModel) -> Bool {
        guard PlatformHostBehavior.favoriteIdentityKey(for: old.liveType) == .userId else {
            return false
        }
        // userId 稳定身份平台:userId 补全,或 userId 仍有效前提下每场换 roomId。
        // 防降级:新 id 必须有效(validIdentity),绝不把有效值回写成空/"0"。
        if let nu = validIdentity(new.userId), validIdentity(old.userId) != nu { return true }
        if validIdentity(new.userId) != nil,
           let nr = validIdentity(new.roomId), validIdentity(old.roomId) != nr { return true }
        return false
    }

    /// 按多维度身份去重(同平台 userId 或 roomId 任一有效维度相同即合并),保留先到的。
    static func deduplicated(_ rooms: [LiveModel]) -> [LiveModel] {
        var byUser: [String: Int] = [:]   // "liveType|userId" -> result 下标
        var byRoom: [String: Int] = [:]   // "liveType|roomId" -> result 下标
        var result: [LiveModel] = []
        result.reserveCapacity(rooms.count)
        for room in rooms {
            let lt = room.liveType.rawValue
            let uKey = validIdentity(room.userId).map { "\(lt)|\($0)" }
            let rKey = validIdentity(room.roomId).map { "\(lt)|\($0)" }
            if let uKey, byUser[uKey] != nil { continue }
            if let rKey, byRoom[rKey] != nil { continue }
            let idx = result.count
            result.append(room)
            if let uKey { byUser[uKey] = idx }
            if let rKey { byRoom[rKey] = idx }
        }
        return result
    }

    /// 收藏同步主键(CKRecord recordName)。按平台 `favoriteIdentityKey` 选主键身份,保留
    /// `_r_/_u_/_n_` 桶前缀,把 ""/"0"/纯空白统一视为"无效"(避免 `_u_0` 这类碰撞桶)。
    ///
    /// - 默认(`.roomId`):roomId 优先、userId 兜底。历史教训:userId 来自各平台插件常空/为 "0"
    ///   (不准),无脑用它当主键会导致同一主播跨时刻/设备生成不同 key → 对不齐、留多份。
    /// - `.userId`(平台 manifest 显式声明):userId 优先、roomId 兜底。用于「roomId 每场会变、
    ///   userId 稳定」的平台,让 recordName 不随 roomId 漂移、同一主播始终一条记录。
    ///
    /// ⚠️ 升级注意:`reKeyRepair.v1` 只跑一次。日后**新增**某平台为 `.userId` 身份时,其存量
    /// recordName 不会自动收敛 —— 那时必须 bump `FavoriteSyncEngine.reKeyRepair` → v2 重跑对账。
    static func favoriteUniqueKey(for room: LiveModel) -> String {
        let liveType = room.liveType.rawValue
        let roomId = validIdentity(room.roomId)
        let userId = validIdentity(room.userId)
        switch PlatformHostBehavior.favoriteIdentityKey(for: room.liveType) {
        case .userId:
            if let userId { return "\(liveType)_u_\(userId)" }
            if let roomId { return "\(liveType)_r_\(roomId)" }
        case .roomId:
            if let roomId { return "\(liveType)_r_\(roomId)" }
            if let userId { return "\(liveType)_u_\(userId)" }
        }
        return "\(liveType)_n_\(room.userName.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
