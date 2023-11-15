//
//  Common.swift
//  SimpleLiveTVOS
//
//  Created by pangchong on 2023/11/14.
//

import Foundation

class Common {
    public class func jsonToData(jsonDic:Dictionary<String, Any>) -> Data? {

        if (!JSONSerialization.isValidJSONObject(jsonDic)) {
            
            print("is not a valid json object")
            
            return nil
        }
        //利用自带的json库转换成Data
        //如果设置options为JSONSerialization.WritingOptions.prettyPrinted，则打印格式更好阅读
        let data = try? JSONSerialization.data(withJSONObject: jsonDic, options: [])
        //Data转换成String打印输出
        let str = String(data:data!, encoding: String.Encoding.utf8)
        //输出json字符串
        print("Json Str:\(str!)")
        return data
    }
}
