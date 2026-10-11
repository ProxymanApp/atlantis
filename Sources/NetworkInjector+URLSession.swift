//
//  NetworkInjector+URLSession.swift
//  atlantis
//
//  Created by Nghia Tran on 10/24/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

func logError(name: String) {
    print("❌ [Atlantis] Could not swizzle this func: \(name)! It looks like the latest iOS (beta) has changed, please contact support@proxyman.io")
}

extension NetworkInjector {

    func _swizzleURLSessionResumeSelector(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("resume")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionResumeSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

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
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionResumeSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        // Start method swizzling
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// urlSession(_:dataTask:didReceive:completionHandler:)
    /// https://developer.apple.com/documentation/foundation/urlsessiondatadelegate/1410027-urlsession
    func _swizzleURLSessionDataTaskDidReceiveResponse(baseClass: AnyClass) {
        // For iOS 16 and later, it uses the same method as iOS 12 and later
        // https://github.com/ProxymanApp/Proxyman/issues/1271
        if #available(iOS 16.0, tvOS 16.0, *) {
            _swizzleURLSessionDataTaskDidReceiveResponseWithoutRewrite(baseClass: baseClass)
        } else if #available(iOS 13.0, tvOS 13.0, *) {
            // Except for the iOS 13, iOS 14, iOS 15, it has a slightly different method
            _swizzleURLSessionDataTaskDidReceiveResponseWithRewrite(baseClass: baseClass)
        } else {
            _swizzleURLSessionDataTaskDidReceiveResponseWithoutRewrite(baseClass: baseClass)
        }
    }

    private func _swizzleURLSessionDataTaskDidReceiveResponseWithRewrite(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_didReceiveResponse:sniff:rewrite:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionDataTaskDidReceiveResponseWithRewrite")
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

    private func _swizzleURLSessionDataTaskDidReceiveResponseWithoutRewrite(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_didReceiveResponse:sniff:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionDataTaskDidReceiveResponseWithoutRewrite")
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
            logError(name: "_swizzleURLSessionDataTaskDidReceiveData")
            return
        }

        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject) -> Void = {[weak self](me, data) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, data)

            // Safe-check with additional nil protection to prevent crashes with NewRelic + airplane mode
            if let task = me.value(forKey: "task") as? URLSessionTask {
                // Additional safety check for data parameter to prevent EXC_BAD_ACCESS
                // when NewRelic interferes with method swizzling in airplane mode
                let safeData: Data? = {
                    guard data != nil else { return nil }
                    return data as? Data
                }()
                if let safeData = safeData {
                    self?.delegate?.injectorSessionDidReceiveData(dataTask: task, data: safeData)
                }
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
            logError(name: "_swizzleURLSessionTaskDidCompleteWithError")
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

// MARK: - Upload

/// Mark an upload task that its body is already reported
private var uploadBodyReportedKey: UInt8 = 0

/// Read the body of an upload from a file
/// Skip a large file: it blocks the thread and Atlantis doesn't send a body larger than MaximumSizePackage anyway
private func uploadBody(fileURL: URL) -> Data? {
    let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    guard fileSize <= NetServiceTransport.MaximumSizePackage else {
        return nil
    }
    return try? Data(contentsOf: fileURL)
}

extension NetworkInjector {

    func _swizzleURLSessionUploadSelector(baseClass: AnyClass) {
        _swizzleURLSessionUploadFromFileSelector(baseClass)
        _swizzleURLSessionUploadFromFileWithCompleteHandlerSelector(baseClass)
        _swizzleURLSessionUploadFromDataSelector(baseClass)
        _swizzleURLSessionUploadFromDataWithCompleteHandlerSelector(baseClass)

        // async/await upload(for:from:delegate:) and upload(for:fromFile:delegate:) don't call the public funcs above
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) {
            _swizzleURLSessionUploadFromDataWithDelegateSelector(baseClass)
            _swizzleURLSessionUploadFromFileWithDelegateSelector(baseClass)
        }
    }

    /// The new loader (NWURLSession) calls the private upload funcs from the public ones,
    /// so we make sure that the body is reported once per task. Otherwise, the body is duplicated
    private func reportUploadIfNeeded(task: URLSessionTask, request: NSURLRequest, data: @autoclosure () -> Data?) {
        guard task.markOnce(&uploadBodyReportedKey) else {
            return
        }
        delegate?.injectorSessionDidUpload(task: task, request: request, data: data())
    }

    private func _swizzleURLSessionUploadFromFileSelector(_ baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("uploadTaskWithRequest:fromFile:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionUploadFromFileSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> AnyObject
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject?) -> AnyObject = {[weak self](me, request, fileURL) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let task = original(me, selector, request, fileURL)

            // Safe-check
            if let task = task as? URLSessionTask,
               let request = request as? NSURLRequest,
               let fileURL = fileURL as? URL {
                self?.reportUploadIfNeeded(task: task, request: request, data: uploadBody(fileURL: fileURL))
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionUploadSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }
            return task
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func _swizzleURLSessionUploadFromFileWithCompleteHandlerSelector(_ baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("uploadTaskWithRequest:fromFile:completionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionUploadFromFileWithCompleteHandlerSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject) -> AnyObject
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject?, AnyObject) -> AnyObject = {[weak self](me, request, fileURL, block) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let task = original(me, selector, request, fileURL, block)

            // Safe-check
            if let task = task as? URLSessionTask,
               let request = request as? NSURLRequest,
                let fileURL = fileURL as? URL {
                self?.reportUploadIfNeeded(task: task, request: request, data: uploadBody(fileURL: fileURL))
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionUploadSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }

            return task
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func _swizzleURLSessionUploadFromDataSelector(_ baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("uploadTaskWithRequest:fromData:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionUploadFromDataSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> AnyObject
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject?) -> AnyObject = {[weak self](me, request, data) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let task = original(me, selector, request, data)

            // Safe-check
            if let task = task as? URLSessionTask,
               let request = request as? NSURLRequest {
                self?.reportUploadIfNeeded(task: task, request: request, data: data as? Data)
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionUploadSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }

            return task
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func _swizzleURLSessionUploadFromDataWithCompleteHandlerSelector(_ baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("uploadTaskWithRequest:fromData:completionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionUploadFromDataWithCompleteHandlerSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject) -> AnyObject
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject?, AnyObject) -> AnyObject = {[weak self](me, request, data, block) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let task = original(me, selector, request, data, block)

            // Safe-check
            if let task = task as? URLSessionTask,
               let request = request as? NSURLRequest {
                self?.reportUploadIfNeeded(task: task, request: request, data: data as? Data)
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionUploadSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }

            return task
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// Used by `upload(for:from:delegate:)` async
    private func _swizzleURLSessionUploadFromDataWithDelegateSelector(_ baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_uploadTaskWithRequest:fromData:delegate:completionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionUploadFromDataWithDelegateSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject?, AnyObject?) -> AnyObject?
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject?, AnyObject?, AnyObject?) -> AnyObject? = {[weak self](me, request, data, taskDelegate, block) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let task = original(me, selector, request, data, taskDelegate, block)

            // Safe-check
            if let task = task as? URLSessionTask,
               let request = request as? NSURLRequest {
                self?.reportUploadIfNeeded(task: task, request: request, data: data as? Data)
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionUploadFromDataWithDelegateSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }

            return task
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// Used by `upload(for:fromFile:delegate:)` async
    private func _swizzleURLSessionUploadFromFileWithDelegateSelector(_ baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("_uploadTaskWithRequest:fromFile:delegate:completionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionUploadFromFileWithDelegateSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, AnyObject?, AnyObject?, AnyObject?) -> AnyObject?
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject?, AnyObject?, AnyObject?) -> AnyObject? = {[weak self](me, request, fileURL, taskDelegate, block) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            let task = original(me, selector, request, fileURL, taskDelegate, block)

            // Safe-check
            if let task = task as? URLSessionTask,
               let request = request as? NSURLRequest,
               let fileURL = fileURL as? URL {
                self?.reportUploadIfNeeded(task: task, request: request, data: uploadBody(fileURL: fileURL))
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionUploadFromFileWithDelegateSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }

            return task
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

// MARK: - WebSocket

extension NetworkInjector {

    /// - Parameter isNetworkLoader: true for NWURLSessionWebSocketTask (the new loader).
    /// It doesn't tell us when the handshake is done, so we check it on every WS event (a cheap check once it's reported),
    /// and the completion handlers report a failed handshake
    func _swizzleURLSessionWebsocketSelector(baseClass: AnyClass, isNetworkLoader: Bool = false) {
        _swizzleURLSessionWebSocketSendMessageSelector(baseClass, isNetworkLoader: isNetworkLoader)
        _swizzleURLSessionWebSocketReceiveMessageSelector(baseClass, isNetworkLoader: isNetworkLoader)
        _swizzleURLSessionWebSocketSendPingPongSelector(baseClass, isNetworkLoader: isNetworkLoader)
        _swizzleURLSessionWebSocketCancelWithCloseCodeReasonSelector(baseClass, isNetworkLoader: isNetworkLoader)
    }

    private func _swizzleURLSessionWebSocketSendMessageSelector(_ baseClass: AnyClass, isNetworkLoader: Bool) {

        // Prepare
        let selector = NSSelectorFromString("sendMessage:completionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionWebSocketSendMessageSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject, AnyObject?) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject, AnyObject?) -> Void = {[weak self] (me, message, block) in

            // On the new loader, the completion handler reports a failed handshake
            let handler = isNetworkLoader ? (self?.wrapNetworkLoaderWebSocketHandler(task: me, handler: block) ?? block) : block

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, message, handler)

            // Safe-check
            if let task = me as? URLSessionTask {
                if isNetworkLoader {
                    self?.reportNetworkLoaderWebSocketHandshakeIfNeeded(task: task, error: nil)
                }

                // As message is `NSURLSessionWebSocketMessage` and Xcode doesn't allow to cast it.
                // We use value(forKey:) to get the value
                if let newMessage = self?.wrapWebSocketMessage(object: message) {
                    self?.delegate?.injectorSessionWebSocketDidSendMessage(task: task, message: newMessage)
                }
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionWebSocketSendMessageSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func _swizzleURLSessionWebSocketReceiveMessageSelector(_ baseClass: AnyClass, isNetworkLoader: Bool) {

        // Prepare
        let selector = NSSelectorFromString("receiveMessageWithCompletionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionWebSocketReceiveMessageSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject) -> Void = {[weak self](me, handler) in

            // Originally implemented in Obj-C.
            let wrapperHandler = AtlantisHelper.swizzleWebSocketReceiveMessage(withCompleteHandler: handler, responseHandler: {[weak self] (str, data, error) in
                if let task = me as? URLSessionTask {
                    if isNetworkLoader {
                        // On iOS 18 (no completeTaskWithError:retryable:), a failed handshake is only reported here
                        self?.reportNetworkLoaderWebSocketHandshakeIfNeeded(task: task, error: error)
                    }
                    if let message = self?.wrapWebSocketMessage(strValue: str, dataValue: data) {
                        self?.delegate?.injectorSessionWebSocketDidReceive(task: task, message: message)
                    }
                } else {
                    print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionWebSocketReceiveMessageSelector. It might causes due to the latest iOS changes. Please contact the author!")
                }
            }) ?? handler

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, wrapperHandler as AnyObject)
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func _swizzleURLSessionWebSocketSendPingPongSelector(_ baseClass: AnyClass, isNetworkLoader: Bool) {

        // Prepare
        let selector = NSSelectorFromString("sendPingWithPongReceiveHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionWebSocketSendPingPongSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = {[weak self](me, handler) in

            // On the new loader, the pong handler reports a failed handshake
            let pongHandler = isNetworkLoader ? (self?.wrapNetworkLoaderWebSocketHandler(task: me, handler: handler) ?? handler) : handler

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, pongHandler)

            // Safe-check
            if let task = me as? URLSessionTask {
                if isNetworkLoader {
                    self?.reportNetworkLoaderWebSocketHandshakeIfNeeded(task: task, error: nil)
                }
                self?.delegate?.injectorSessionWebSocketDidSendPingPong(task: task)
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionWebSocketSendPingPongSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func _swizzleURLSessionWebSocketCancelWithCloseCodeReasonSelector(_ baseClass: AnyClass, isNetworkLoader: Bool) {

        // Prepare
        let selector = NSSelectorFromString("cancelWithCloseCode:reason:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleURLSessionWebSocketCancelWithCloseCodeReasonSelector")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, NSInteger, AnyObject?) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, NSInteger, AnyObject?) -> Void = {[weak self](me, closeCode, reason) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, closeCode, reason)

            // Safe-check
            if let task = me as? URLSessionTask {
                if isNetworkLoader {
                    self?.reportNetworkLoaderWebSocketHandshakeIfNeeded(task: task, error: nil)
                }
                let newCloseCode = URLSessionWebSocketTask.CloseCode(rawValue: closeCode) ?? .invalid
                let data = reason as? Data // optional data
                self?.delegate?.injectorSessionWebSocketDidSendCancelWithReason(task: task, closeCode: newCloseCode, reason: data)
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleURLSessionWebSocketCancelWithCloseCodeReasonSelector. It might causes due to the latest iOS changes. Please contact the author!")
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private func wrapWebSocketMessage(object: AnyObject) -> URLSessionWebSocketTask.Message? {
        if let strValue = object.value(forKey: "string") as? String {
            return URLSessionWebSocketTask.Message.string(strValue)
        } else if let dataValue = object.value(forKey: "data") as? Data {
            return URLSessionWebSocketTask.Message.data(dataValue)
        }
        return nil
    }

    private func wrapWebSocketMessage(strValue: String?, dataValue: Data?) -> URLSessionWebSocketTask.Message? {
        if let strValue = strValue {
            return URLSessionWebSocketTask.Message.string(strValue)
        } else if let dataValue = dataValue {
            return URLSessionWebSocketTask.Message.data(dataValue)
        }
        return nil
    }
}
