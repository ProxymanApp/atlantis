//
//  Runtime.swift
//  atlantis
//
//  Created by Nghia Tran on 10/24/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

struct Runtime {

    static func getAllClasses() -> [AnyClass] {
        let expectedClassCount = objc_getClassList(nil, 0)
        let allClasses = UnsafeMutablePointer<AnyClass?>.allocate(capacity: Int(expectedClassCount))

        let autoreleasingAllClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        let actualClassCount: Int32 = objc_getClassList(autoreleasingAllClasses, expectedClassCount)

        var classes = [AnyClass]()
        for i in 0 ..< actualClassCount {
            if let currentClass: AnyClass = allClasses[Int(i)] {
                classes.append(currentClass)
            }
        }

        allClasses.deallocate()
        return classes
    }
}
