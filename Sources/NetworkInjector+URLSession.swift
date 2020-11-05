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

        // 
        typealias NewClosureType =  @convention(c) (AnyObject, Selector) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject) -> Void = {[weak self](me) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector)


            // If it's from Atlantis, skip it
            if let task = me as? URLSessionTask,
               task.isFromAtlantisFramework() {
                return
            }

            // Safe-check
            if let task = me as? URLSessionTask {
                self?.delegate?.injectorSessionDidCallResume(task: task)
            } else {
                assertionFailure("Could not get data from _swizzleURLSessionResumeSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        // Start method swizzling
        method_setImplementation(method, imp_implementationWithBlock(block))
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

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, Bool, Bool) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, Bool, Bool) -> Void = {[weak self](me, response, sniff, rewrite) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, response, sniff, rewrite)

            // Safe-check
            if let task = me.value(forKey: "task") as? URLSessionTask,
               let response = response as? URLResponse {
                self?.delegate?.injectorSessionDidReceiveResponse(dataTask: task, response: response)
            } else {
                assertionFailure("Could not get data from _swizzleURLSessionDataTaskDidReceiveResponseForIOS13AndLater. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func _swizzleURLSessionDataTaskDidReceiveResponseForBelowIOS13(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_didReceiveResponse:sniff:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            return
        }

        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, Bool) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, Bool) -> Void = {[weak self](me, response, sniff) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, response, sniff)

            // Safe-check
            if let task = me.value(forKey: "task") as? URLSessionTask,
               let response = response as? URLResponse {
                self?.delegate?.injectorSessionDidReceiveResponse(dataTask: task, response: response)
            } else {
                assertionFailure("Could not get data from _swizzleURLSessionDataTaskDidReceiveResponseForBelowIOS13. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
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

        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject) -> Void = {[weak self](me, data) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, data)

            // Safe-check
            if let task = me.value(forKey: "task") as? URLSessionTask,
               let data = data as? Data {
                self?.delegate?.injectorSessionDidReceiveData(dataTask: task, data: data)
            } else {
                assertionFailure("Could not get data from _swizzleURLSessionDataTaskDidReceiveData. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
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

        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = {[weak self](me, error) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, error)

            // Safe-check
            if let task = me.value(forKey: "task") as? URLSessionTask {
                let error = error as? Error
                self?.delegate?.injectorSessionDidComplete(task: task, error: error)
            } else {
                assertionFailure("Could not get data from _swizzleURLSessionTaskDidCompleteWithError. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
