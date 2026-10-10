//
//  NetworkInjector.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

struct NetworkConfiguration {

    /// Whether or not Atlantis should perform the Method Swizzling on WS/WSS connection.
    let shouldCaptureWebSocketTraffic: Bool

    // init
    init(shouldCaptureWebSocketTraffic: Bool = true) {
        self.shouldCaptureWebSocketTraffic = shouldCaptureWebSocketTraffic
    }
}

protocol Injector {

    var delegate: InjectorDelegate? { get set }
    func injectAllNetworkClasses(config: NetworkConfiguration)
}

protocol InjectorDelegate: AnyObject {

    // For URLSession
    func injectorSessionDidCallResume(task: URLSessionTask)
    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse)
    func injectorSessionDidReceiveData(dataTask: URLSessionTask, data: Data)
    func injectorSessionDidComplete(task: URLSessionTask, error: Error?)
    func injectorSessionDidUpload(task: URLSessionTask, request: NSURLRequest, data: Data?)

    // Websocket
    func injectorSessionWebSocketDidSendMessage(task: URLSessionTask, message: URLSessionWebSocketTask.Message)
    func injectorSessionWebSocketDidReceive(task: URLSessionTask, message: URLSessionWebSocketTask.Message)
    func injectorSessionWebSocketDidSendPingPong(task: URLSessionTask)
    func injectorSessionWebSocketDidSendCancelWithReason(task: URLSessionTask, closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

final class NetworkInjector: Injector {

    // MARK: - Variables

    weak var delegate: InjectorDelegate?

    /// Methods that are already swizzled.
    /// The same func is swizzled on many classes (e.g. the classic and the new URLSession loader),
    /// if the classes share an implementation, it must be swizzled once. Otherwise, the traffic is captured twice.
    private var swizzledMethods = Set<OpaquePointer>()

    // MARK: - Internal

    /// Return false if the method was already swizzled
    func markAsSwizzled(_ method: Method) -> Bool {
        return swizzledMethods.insert(method).inserted
    }

    func injectAllNetworkClasses(config: NetworkConfiguration = NetworkConfiguration()) {
        // Make sure we swizzle *ONCE*
        DispatchQueue.once {
            injectAllURLSession(config)
        }
    }
}

extension NetworkInjector {

    private func injectAllURLSession(_ config: NetworkConfiguration) {

        // iOS 8: __NSCFURLSessionConnection
        // iOS 9, 10, 11, 12, 13, 14: __NSCFURLLocalSessionConnection
        // This approach works with delegate or complete block from URLSession
        let sessionClass: AnyClass? = NSClassFromString("__NSCFURLLocalSessionConnection") ?? NSClassFromString("__NSCFURLSessionConnection")

        if let anySessionClass = sessionClass {
            injectIntoURLSessionDelegate(anyClass: anySessionClass)
        }

        // Resume
        injectURLSessionResume()

        // Upload
        injectURLSessionUploadTasks()

        // Websocket
        // Able to opt-out the WS/WSS if needed
        if config.shouldCaptureWebSocketTraffic {
            injectURLSessionWebsocketTasks()
        }

        // The new loader, used when URLSessionConfiguration.usesClassicLoadingMode is false
        injectNetworkLoaderURLSession(config)
    }

    private func injectIntoURLSessionDelegate(anyClass: AnyClass) {
        _swizzleURLSessionDataTaskDidReceiveResponse(baseClass: anyClass)
        _swizzleURLSessionDataTaskDidReceiveData(baseClass: anyClass)
        _swizzleURLSessionTaskDidCompleteWithError(baseClass: anyClass)
    }

    private func injectURLSessionResume() {
        // In iOS 7 resume lives in __NSCFLocalSessionTask
        // In iOS 8 resume lives in NSURLSessionTask
        // In iOS 9 resume lives in __NSCFURLSessionTask
        // In iOS 14 resume lives in NSURLSessionTask
        var baseResumeClass: AnyClass? = nil;
        if !ProcessInfo.processInfo.responds(to: #selector(getter: ProcessInfo.operatingSystemVersion)) {
            baseResumeClass = NSClassFromString("__NSCFLocalSessionTask")
        } else {
            // watchOS and visionOS are versioned differently, but they always use NSURLSessionTask (same as iOS 14+)
            #if targetEnvironment(macCatalyst) || os(macOS) || os(watchOS) || os(visionOS)
            baseResumeClass = URLSessionTask.self
            #else
            let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            if majorVersion < 9 || majorVersion >= 14 {
                baseResumeClass = URLSessionTask.self
            } else {
                baseResumeClass = NSClassFromString("__NSCFURLSessionTask")
            }
            #endif
        }

        guard let resumeClass = baseResumeClass else {
            assertionFailure("Could not find URLSessionTask. Please open support ticket at https://github.com/ProxymanApp/atlantis")
            return
        }

        _swizzleURLSessionResumeSelector(baseClass: resumeClass)
    }

    private func injectURLSessionUploadTasks() {
        _swizzleURLSessionUploadSelector(baseClass: URLSession.self)
    }

    private func injectURLSessionWebsocketTasks() {
        guard let websocketClass = NSClassFromString("__NSURLSessionWebSocketTask") else {
            print("[Atlantis][ERROR] Could not inject __NSURLSessionWebSocketTask!!")
            return
        }
        _swizzleURLSessionWebsocketSelector(baseClass: websocketClass)
    }

    /// iOS 18.4+, macOS 15.4+, tvOS 18.4+, watchOS 11.4+, visionOS 2.4+ ship a second URLSession loader built on Network.framework.
    /// URLSession switches to it when `URLSessionConfiguration.usesClassicLoadingMode` is false,
    /// which is required by newer APIs, e.g. `enablesEarlyData` (HTTP/3 0-RTT) in iOS 26.
    /// Its classes (NWURLSession, NWURLSessionTask, ...) don't inherit from NSURLSession/NSURLSessionTask, so the classic swizzling doesn't see them.
    private func injectNetworkLoaderURLSession(_ config: NetworkConfiguration) {
        guard let sessionClass = NSClassFromString("NWURLSession"),
              let taskClass = NSClassFromString("NWURLSessionTask") else {
            // Older OS, there is only the classic loader
            return
        }

        // Resume
        _swizzleURLSessionResumeSelector(baseClass: taskClass)

        // Upload
        _swizzleURLSessionUploadSelector(baseClass: sessionClass)

        // Response, Data and Completion are delivered to a response consumer,
        // one for each kind of task (completion handler, delegate, download)
        for consumerName in ["NWURLSessionResponseConsumerDataCompletionHandler",
                             "NWURLSessionResponseConsumerDataDelegate",
                             "NWURLSessionResponseConsumerDownload"] {
            guard let consumerClass = NSClassFromString(consumerName) else {
                logError(name: consumerName)
                continue
            }
            _swizzleNWURLSessionConsumerDeliverResponse(baseClass: consumerClass)
            _swizzleNWURLSessionConsumerDeliverData(baseClass: consumerClass)
        }

        // Websocket
        if config.shouldCaptureWebSocketTraffic {
            guard let websocketClass = NSClassFromString("NWURLSessionWebSocketTask") else {
                logError(name: "NWURLSessionWebSocketTask")
                return
            }
            _swizzleURLSessionWebsocketSelector(baseClass: websocketClass, isNetworkLoader: true)
            _swizzleNWURLSessionTaskLoaderConnected(baseClass: taskClass)

            // Not on iOS 18 / macOS 15. The receive hook reports a failed handshake too
            if websocketClass.instancesRespond(to: NSSelectorFromString("completeTaskWithError:retryable:")) {
                _swizzleNWURLSessionWebSocketTaskComplete(baseClass: websocketClass)
            }
        }
    }
}
