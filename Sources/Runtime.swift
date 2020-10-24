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

    static func getAllMethods(from baseClass: AnyClass) -> [Method] {
        var methods = [Method]()
        let count = UnsafeMutablePointer<UInt32>.allocate(capacity: 0)
        guard let methodList = class_copyMethodList(baseClass, count) else { return methods }

        for methodCount in 0..<count.pointee {
            let method = methodList[Int(methodCount)]
            methods.append(method)
        }

        count.deallocate()
        methodList.deallocate()
        return methods
    }
}
