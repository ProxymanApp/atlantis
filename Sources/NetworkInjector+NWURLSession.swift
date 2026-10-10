//
//  NetworkInjector+NWURLSession.swift
//  atlantis
//
//  Copyright © 2026 Proxyman. All rights reserved.
//

import Foundation

/// Mark a WebSocket task that its handshake is already reported
private var webSocketHandshakeReportedKey: UInt8 = 0
private let webSocketHandshakeLock = NSLock()

// MARK: - New URLSession loader (NWURLSession)
//
// When `URLSessionConfiguration.usesClassicLoadingMode` is false, URLSession runs on Network.framework:
// NWURLSession creates NWURLSessionTask, which doesn't inherit from NSURLSessionTask, but answers `isKind(of: URLSessionTask.self)`.
// There is no __NSCFURLLocalSessionConnection, a response consumer receives the response and the body instead:
// - NWURLSessionResponseConsumerDataCompletionHandler: completion handler and async/await (data(for:), upload(for:from:), ...)
// - NWURLSessionResponseConsumerDataDelegate: tasks with a delegate, bytes(for:)
// - NWURLSessionResponseConsumerDownload: download tasks

extension NetworkInjector {

    /// -[NWURLSessionResponseConsumer task:deliverResponse:completionHandler:]
    func _swizzleNWURLSessionConsumerDeliverResponse(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("task:deliverResponse:completionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleNWURLSessionConsumerDeliverResponse")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject?, AnyObject?, AnyObject?) -> Void = {[weak self](me, task, response, handler) in

            // Get the response before calling the original
            // The body might be delivered from another thread right after the original is called
            if let task = task as? URLSessionTask,
               let response = response as? URLResponse {
                self?.delegate?.injectorSessionDidReceiveResponse(dataTask: task, response: response)
            } else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleNWURLSessionConsumerDeliverResponse. It might causes due to the latest iOS changes. Please contact the author!")
            }

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, task, response, handler)
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// -[NWURLSessionResponseConsumer task:deliverData:complete:error:completionHandler:]
    /// The body comes in chunks. The last call has complete = true, even if there is no body or the task fails
    func _swizzleNWURLSessionConsumerDeliverData(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("task:deliverData:complete:error:completionHandler:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleNWURLSessionConsumerDeliverData")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, Bool, AnyObject?, AnyObject?) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject?, AnyObject?, Bool, AnyObject?, AnyObject?) -> Void = {[weak self](me, task, data, isComplete, error, handler) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, task, data, isComplete, error, handler)

            // Safe-check
            guard let task = task as? URLSessionTask else {
                print("[Atlantis] ❌ Error: Could not get data from _swizzleNWURLSessionConsumerDeliverData. It might causes due to the latest iOS changes. Please contact the author!")
                return
            }

            // It's a dispatch_data_t, which is bridged to NSData
            if let data = data as? Data, !data.isEmpty {
                self?.delegate?.injectorSessionDidReceiveData(dataTask: task, data: data)
            }
            if isComplete {
                self?.delegate?.injectorSessionDidComplete(task: task, error: error as? Error)
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

// MARK: - WebSocket

extension NetworkInjector {

    /// -[NWURLSessionTask loaderConnectedWithHTTPConnectionMetadata:CNAMEChain:unlistedTracker:]
    /// For WebSocket, it's called when the connection is ready, then after the handshake. The response (101) is available at the second call
    func _swizzleNWURLSessionTaskLoaderConnected(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("loaderConnectedWithHTTPConnectionMetadata:CNAMEChain:unlistedTracker:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleNWURLSessionTaskLoaderConnected")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject?, AnyObject?, AnyObject?) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject?, AnyObject?, AnyObject?) -> Void = {[weak self](me, metadata, cnameChain, unlistedTracker) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, metadata, cnameChain, unlistedTracker)

            // Only for WebSocket, other tasks get the response from the response consumer
            if let task = me as? URLSessionWebSocketTask {
                self?.reportNetworkLoaderWebSocketHandshakeIfNeeded(task: task, error: nil)
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// -[NWURLSessionWebSocketTask completeTaskWithError:retryable:]
    /// It's the only callback if the handshake fails, e.g. the server is down or it rejects the upgrade
    func _swizzleNWURLSessionWebSocketTaskComplete(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("completeTaskWithError:retryable:")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            logError(name: "_swizzleNWURLSessionWebSocketTaskComplete")
            return
        }
        guard markAsSwizzled(method) else { return }

        // For safety, we should cast to AnyObject
        // To prevent app crashes in the future if the object type is changed
        typealias NewClosureType =  @convention(c) (AnyObject, Selector, AnyObject?, Bool) -> Void
        let originalImp: IMP = method_getImplementation(method)
        let block: @convention(block) (AnyObject, AnyObject?, Bool) -> Void = {[weak self](me, error, retryable) in

            // call the original
            let original: NewClosureType = unsafeBitCast(originalImp, to: NewClosureType.self)
            original(me, selector, error, retryable)

            // Do nothing if the handshake is reported, e.g. the WebSocket is closed
            if !retryable, let task = me as? URLSessionWebSocketTask {
                self?.reportNetworkLoaderWebSocketHandshakeIfNeeded(task: task, error: error as? Error)
            }
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// The classic loader reports the WebSocket handshake as a normal request: the response (101), then the completion.
    /// Do the same for the new loader, once per task
    func reportNetworkLoaderWebSocketHandshakeIfNeeded(task: URLSessionTask, error: Error?) {
        // Wait for the response, unless the handshake failed
        let response = task.response
        guard response != nil || error != nil else {
            return
        }

        webSocketHandshakeLock.lock()
        let isReported = objc_getAssociatedObject(task, &webSocketHandshakeReportedKey) != nil
        if !isReported {
            objc_setAssociatedObject(task, &webSocketHandshakeReportedKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        webSocketHandshakeLock.unlock()
        guard !isReported else {
            return
        }

        if let response = response {
            delegate?.injectorSessionDidReceiveResponse(dataTask: task, response: response)
        }
        delegate?.injectorSessionDidComplete(task: task, error: error)
    }
}
