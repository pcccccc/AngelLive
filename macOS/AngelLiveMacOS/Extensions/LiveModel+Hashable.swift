//
//  LiveModel+Hashable.swift
//  AngelLiveMacOS
//
//  Created by pc on 11/11/25.
//  Supported by AI助手Claude
//

import Foundation
import LiveParse

extension LiveModel: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
