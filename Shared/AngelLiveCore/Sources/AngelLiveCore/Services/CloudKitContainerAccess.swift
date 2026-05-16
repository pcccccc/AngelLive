//
//  CloudKitContainerAccess.swift
//  AngelLiveCore
//
//  Centralized guard before touching CKContainer. Personal development
//  profiles can install the app without iCloud entitlement; initializing a
//  named CKContainer in that state traps before Swift can catch an error.
//

import CloudKit
import Foundation

enum CloudKitContainerAccess {
    private static let iCloudContainerEntitlementKey = "com.apple.developer.icloud-container-identifiers"

    static func privateDatabase(
        containerIdentifier: String,
        purpose: String,
        category: LogCategory = .cloudKit
    ) -> CKDatabase? {
        guard hasICloudContainer(containerIdentifier) else {
            Logger.info("当前签名未包含 iCloud entitlement，跳过\(purpose)", category: category)
            return nil
        }
        return CKContainer(identifier: containerIdentifier).privateCloudDatabase
    }

    static func container(
        identifier: String,
        purpose: String,
        category: LogCategory = .cloudKit
    ) -> CKContainer? {
        guard hasICloudContainer(identifier) else {
            Logger.info("当前签名未包含 iCloud entitlement，跳过\(purpose)", category: category)
            return nil
        }
        return CKContainer(identifier: identifier)
    }

    static func hasICloudContainer(_ identifier: String) -> Bool {
        guard !identifier.isEmpty else { return false }

        #if os(iOS) || os(tvOS)
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            // App Store packages normally omit embedded.mobileprovision; trust the signed entitlement there.
            return true
        }
        guard let entitlements = embeddedProvisioningEntitlements(at: url) else {
            return false
        }

        if let containers = entitlements[iCloudContainerEntitlementKey] as? [String] {
            return containers.contains(identifier)
        }
        if let container = entitlements[iCloudContainerEntitlementKey] as? String {
            return container == identifier
        }
        return false
        #else
        return true
        #endif
    }

    #if os(iOS) || os(tvOS)
    /// Debug/AdHoc builds include a CMS mobileprovision file with an embedded plist.
    private static func embeddedProvisioningEntitlements(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            return nil
        }

        let plistData = Data(data[start.lowerBound..<end.upperBound])
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }
        return plist["Entitlements"] as? [String: Any]
    }
    #endif
}
