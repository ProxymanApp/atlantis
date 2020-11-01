//
//  PackageIdentifier.swift
//  atlantis
//
//  Created by Nghia Tran on 10/24/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

struct PackageIdentifier {

    static var PackageIDKey: UInt8 = 0

    static func getID(taskOrConnection: AnyObject) -> String {
        if let requestID = objc_getAssociatedObject(taskOrConnection, &PackageIDKey) as? String {
            return requestID
        }

        let id = UUID().uuidString
        objc_setAssociatedObject(taskOrConnection, &PackageIDKey, id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return id
    }
}
