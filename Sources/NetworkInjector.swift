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

    // MARK: - Internal

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
        // We don't need to swizzle resume method because when the request is resumed, the request doens't have full request headers yet
        // Some headers are added after the request is resumed
        // If we swizzle resume method, it will cause the request headers to be missing
        // 
        // Solution: Get the request headers when the Response is received
//        injectURLSessionResume()

        // Upload
        injectURLSessionUploadTasks()

        // Websocket
        // Able to opt-out the WS/WSS if needed
        if config.shouldCaptureWebSocketTraffic {
            injectURLSessionWebsocketTasks()
        }
    }

    private func injectIntoURLSessionDelegate(anyClass: AnyClass) {
        _swizzleURLSessionDataTaskDidReceiveResponse(baseClass: anyClass)
        _swizzleURLSessionDataTaskDidReceiveData(baseClass: anyClass)
        _swizzleURLSessionTaskDidCompleteWithError(baseClass: anyClass)
    }

    private func injectURLSessionUploadTasks() {
        _swizzleURLSessionUploadSelector(baseClass: URLSession.self)
    }

    private func injectURLSessionWebsocketTasks() {
        _swizzleURLSessionWebsocketSelector()
    }
}
