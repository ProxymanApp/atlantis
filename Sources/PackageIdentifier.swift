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

    static func getID(task: URLSessionTask) -> String {
        if let requestID = objc_getAssociatedObject(task, &PackageIDKey) as? String {
            return requestID
        }

        let id = UUID().uuidString
        objc_setAssociatedObject(task, &PackageIDKey, id, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return id
    }
}
