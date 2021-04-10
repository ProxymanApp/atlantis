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

    static func getAllMethod(anyClass: AnyClass) -> [String] {
        var methods: [String] = []
        var methodCount: UInt32 = 0
        let methodList = class_copyMethodList(anyClass, &methodCount)
        for i in 0 ..< Int(methodCount) {
            let selName = sel_getName(method_getName(methodList![i]))
            let name = String(cString: selName)
            methods.append(name)
        }
        return methods
    }
}

/// A simple atomic lock
/// We might consider using swift-atomic in the future
/// https://github.com/apple/swift-atomics
final class Atomic<A> {

    private let queue = DispatchQueue(label: "com.proxyman.atlantis.atomic")
    private var _value: A

    init(_ value: A) {
        self._value = value
    }

    var value: A {
        get {
            return queue.sync { self._value }
        }
    }

    func mutate(_ transform: (inout A) -> ()) {
        queue.sync {
            transform(&self._value)
        }
    }
}

extension URLSessionTask {

    static var AtlantisIDKey: UInt8 = 0

    func setFromAtlantisFramework() {
        objc_setAssociatedObject(self, &URLSessionStreamTask.AtlantisIDKey, "_atlantis_URLSessionStreamTask", .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func isFromAtlantisFramework() -> Bool {
        if let _ = objc_getAssociatedObject(self, &URLSessionStreamTask.AtlantisIDKey) as? String {
            return true
        }
        return false
    }
}

/// Status codes for gRPC operations (replicated from status_code_enum.h)
enum GRPCStatusCode: Int {
    /// Not an error; returned on success.
    case ok = 0
    case cancelled = 1
    case unknown = 2
    case invalidArgument = 3
    case deadlineExceeded = 4
    case notFound = 5
    case alreadyExists = 6
    case permissionDenied = 7
    case unauthenticated = 16
    case resourceExhausted = 8
    case failedPrecondition = 9
    case aborted = 10
    case outOfRange = 11
    case unimplemented = 12
    case internalError = 13
    case unavailable = 14
    case dataLoss = 15
    case doNotUse = -1

    var description: String {
        return "\(self) (code=\(rawValue))"
    }
}
