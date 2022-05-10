//
//  NetworkInjector.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

protocol Injector {

    var delegate: InjectorDelegate? { get set }
    func injectAllNetworkClasses()
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

    // MARK: - Internal

    func injectAllNetworkClasses() {
        // Make sure we swizzle *ONCE*
        DispatchQueue.once {
            injectAllURLSession()
        }
    }
}

extension NetworkInjector {

    private func injectAllURLSession() {

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
        injectURLSessionWebsocketTasks()
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
            #if targetEnvironment(macCatalyst) || os(macOS)
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
        _swizzleURLSessionWebsocketSelector()
    }
}
