//
//  Runtime.swift
//  atlantis
//
//  Created by Nghia Tran on 10/24/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

struct Runtime {

    static func getAllClassesConformsProtocol(_ aProtocol: Protocol) -> [AnyClass] {
        var numberClasses: UInt32 = 0
        var result = Array<AnyClass>()
        if let classes = UnsafePointer(objc_copyClassList(&numberClasses)) {
            for i in 0..<Int(numberClasses) {
                let aClass: AnyClass = classes[i]
                if class_conformsToProtocol(aClass, aProtocol) {
                    result.append(aClass)
                }
            }
            free(UnsafeMutableRawPointer(mutating: classes))
        }
        return result
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
