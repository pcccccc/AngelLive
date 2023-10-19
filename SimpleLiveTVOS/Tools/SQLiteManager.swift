//
//  SQLiteManager.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/10/11.
//

import Foundation
import SQLite

let roomId_column = Expression<String>("roomId")
let userId_column = Expression<String>("userId")
let userName_column = Expression<String>("userName")
let roomTitle_column = Expression<String>("roomTitle")
let roomCover_column = Expression<String>("roomCover")
let userHeadImg_column = Expression<String>("userHeadImg")
let liveType_column =  Expression<LiveType.RawValue.ValueType>("liveType")
let liveState_column = Expression<String>("liveState")
let id_column = rowid


class SQLiteManager: NSObject {
    
    static let manager = SQLiteManager()
    private var db: Connection?
    private var table: Table?
    
    func getDB() -> Connection {
        if db == nil {
            let path = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first!
            db = try! Connection("\(path)/db.sqlite3")
            db?.busyTimeout = 3
        }
        return db!
    }
    
    func getTable() -> Table {
        if table == nil {
            table = Table("favorite_live")
            try! getDB().run(
            
                table!.create(temporary: false, ifNotExists: true, withoutRowid: false, block: { builder in
                    builder.column(roomId_column)
                    builder.column(userId_column)
                    builder.column(userName_column)
                    builder.column(roomTitle_column)
                    builder.column(roomCover_column)
                    builder.column(userHeadImg_column)
                    builder.column(liveType_column)
                    builder.column(liveState_column)
                })
            )
        }
        return table!
    }
    
    func insert(item: LiveModel) -> Bool {
        let insert = getTable().insert(
            roomId_column <- item.roomId,
            userId_column <- item.userId,
            userName_column <- item.userName,
            roomTitle_column <- item.roomTitle,
            roomCover_column <- item.roomCover,
            userHeadImg_column <- item.userHeadImg,
            liveType_column <- item.liveType.rawValue,
            liveState_column <- item.liveState ?? ""
        )
        if (try? getDB().run(insert)) != nil {
            return true
        }else {
            return false
        }
    }
    
    func delete(roomId: String) -> Bool {
       return delete(filter: roomId == roomId_column)
    }
    
    func delete(filter: Expression<Bool>? = nil) -> Bool {
        var query = getTable()
        if let f = filter {
            query = query.filter(f)
        }
        if let count = try? getDB().run(query.delete()) {
            return true
        }else {
            return false
        }
        
    }
    
    func search(page: Int) -> [LiveModel] {
        let query = getTable().select([id_column, roomId_column, userId_column, userName_column, roomTitle_column, roomCover_column, userHeadImg_column, liveType_column, liveState_column]).limit(10, offset: page)
        let res = try! getDB().prepare(query)
        var array: Array<LiveModel> = []
        for item in res {
            array.append(LiveModel(userName: item[userName_column], roomTitle: item[roomTitle_column], roomCover: item[roomCover_column], userHeadImg: item[userHeadImg_column], liveType: LiveType(rawValue: item[liveType_column])!, liveState: item[liveState_column], userId: item[userId_column], roomId: item[roomId_column]))
        }
        return array
    }
    
    func search(roomId: String) -> LiveModel? {
        let query = getTable().select([id_column, roomId_column, userId_column, userName_column, roomTitle_column, roomCover_column, userHeadImg_column, liveType_column, liveState_column]).filter(roomId == roomId_column)
         let res = try! getDB().prepare(query)
        var array: Array<LiveModel> = []
        for item in res {
            array.append(LiveModel(userName: item[userName_column], roomTitle: item[roomTitle_column], roomCover: item[roomCover_column], userHeadImg: item[userHeadImg_column], liveType: LiveType(rawValue: item[liveType_column])!, liveState: item[liveState_column], userId: item[userId_column], roomId: item[roomId_column]))
        }
        if array.count == 0 {
            return nil
        }else {
            return array.first!
        }
    }
}


