//
//  NetworkInjector+URLSession.swift
//  atlantis
//
//  Created by Nghia Tran on 10/24/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

extension NetworkInjector {

    func _swizzleURLSessionResumeSelector(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("resume")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            return
        }

        // Get original method to call later
        let originalIMP = method_getImplementation(method)

        // swizzle the original with the new one and start intercepting the content
        let swizzleIMP = imp_implementationWithBlock({[weak self](slf: URLSessionTask) -> Void in

            // Notify
            self?.delegate?.injectorSessionDidCallResume(task: slf)

            // Make sure the original method is called
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSessionTask, Selector) -> Void).self)
            oldIMP(slf, selector)
            } as @convention(block) (URLSessionTask) -> Void)

        //
        method_setImplementation(method, swizzleIMP)
    }

    /// urlSession(_:dataTask:didReceive:completionHandler:)
    /// https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1410027-urlsession
    func _swizzleURLSessionDataTaskDidReceiveResponse(baseClass: AnyClass) {
        if #available(iOS 13.0, *) {
            _swizzleURLSessionDataTaskDidReceiveResponseForIOS13AndLater(baseClass: baseClass)
        } else {
            _swizzleURLSessionDataTaskDidReceiveResponseForBelowIOS13(baseClass: baseClass)
        }
    }

    func _swizzleURLSessionDataTaskDidReceiveResponseForIOS13AndLater(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_didReceiveResponse:sniff:rewrite:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            return
        }

        // Get original method to call later
        let originalIMP = method_getImplementation(method)

        // swizzle the original with the new one and start intercepting the content
        let swizzleIMP = imp_implementationWithBlock({[weak self](slf: AnyObject, response: URLResponse, sniff: Bool, rewirte: Bool) -> Void in

            // Safe-check
            if let task = slf.value(forKey: "task") as? URLSessionDataTask {
                self?.delegate?.injectorSessionDidReceiveResponse(dataTask: task, response: response)
            } else {
                assertionFailure("Could not get URLSessionDataTask from _swizzleURLSessionDataTaskDidReceiveResponse. It might causes due to the latest iOS changes. Please contact the author!")
            }

            // Make sure the original method is called
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector, URLResponse, Bool, Bool) -> Void).self)
            oldIMP(slf, selector, response, sniff, rewirte)
            } as @convention(block) (AnyObject, URLResponse, Bool, Bool) -> Void)

        //
        method_setImplementation(method, swizzleIMP)
    }

    private func _swizzleURLSessionDataTaskDidReceiveResponseForBelowIOS13(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_didReceiveResponse:sniff:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            return
        }

        // Get original method to call later
        let originalIMP = method_getImplementation(method)

        // swizzle the original with the new one and start intercepting the content
        let swizzleIMP = imp_implementationWithBlock({[weak self](slf: AnyObject, response: URLResponse, sniff: Bool) -> Void in

            // Safe-check
            if let task = slf.value(forKey: "task") as? URLSessionDataTask {
                self?.delegate?.injectorSessionDidReceiveResponse(dataTask: task, response: response)
            } else {
                assertionFailure("Could not get URLSessionDataTask from _swizzleURLSessionDataTaskDidReceiveResponse. It might causes due to the latest iOS changes. Please contact the author!")
            }

            // Make sure the original method is called
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector, URLResponse, Bool) -> Void).self)
            oldIMP(slf, selector, response, sniff)
            } as @convention(block) (AnyObject, URLResponse, Bool) -> Void)

        //
        method_setImplementation(method, swizzleIMP)
    }

    /// urlSession(_:dataTask:didReceive:)
    /// https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1411528-urlsession
    func _swizzleURLSessionDataTaskDidReceiveData(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_didReceiveData:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            return
        }

        // Get original method to call later
        let originalIMP = method_getImplementation(method)

        // swizzle the original with the new one and start intercepting the content
        let swizzleIMP = imp_implementationWithBlock({[weak self](slf: AnyObject, data: Data) -> Void in

            // Safe-check
            if let task = slf.value(forKey: "task") as? URLSessionDataTask {
                self?.delegate?.injectorSessionDidReceiveData(dataTask: task, data: data)
            } else {
                assertionFailure("Could not get URLSessionDataTask from _swizzleURLSessionDataTaskDidReceiveData. It might causes due to the latest iOS changes. Please contact the author!")
            }

            // Make sure the original method is called
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector, Data) -> Void).self)
            oldIMP(slf, selector, data)
            } as @convention(block) (AnyObject, Data) -> Void)

        //
        method_setImplementation(method, swizzleIMP)
    }

    /// urlSession(_:task:didCompleteWithError:)
    /// https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/1411610-urlsession
    func _swizzleURLSessionTaskDidCompleteWithError(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_didFinishWithError:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            return
        }

        // Get original method to call later
        let originalIMP = method_getImplementation(method)

        // swizzle the original with the new one and start intercepting the content
        let swizzleIMP = imp_implementationWithBlock({[weak self](slf: AnyObject, error: Error?) -> Void in

            // Safe-check
            if let task = slf.value(forKey: "task") as? URLSessionTask {
                self?.delegate?.injectorSessionDidComplete(task: task, error: error)
            } else {
                assertionFailure("Could not get URLSessionTask from _swizzleURLSessionTaskDidCompleteWithError. It might causes due to the latest iOS changes. Please contact the author!")
            }

            // Make sure the original method is called
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (AnyObject, Selector, Error?) -> Void).self)
            oldIMP(slf, selector, error)
            } as @convention(block) (AnyObject, Error?) -> Void)

        //
        method_setImplementation(method, swizzleIMP)
    }
}
