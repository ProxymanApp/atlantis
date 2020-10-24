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

protocol InjectorDelegate: class {

    func injectorSessionDidCallResume(task: URLSessionTask)
    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse)
    func injectorSessionDidReceiveData(dataTask: URLSessionDataTask, data: Data)
    func injectorSessionDidComplete(task: URLSessionTask, error: Error?)
}

final class NetworkInjector: Injector {

    // MARK: - Variables

    weak var delegate: InjectorDelegate?

    // MARK: - Internal

    func injectAllNetworkClasses() {
        // Make sure we swizzle *ONCE*
        DispatchQueue.once {
            injectAllURLSessionDelegate()
            injectURLSessionResume()
        }
    }
}

extension NetworkInjector {

    private func injectAllURLSessionDelegate() {
        let allClasses = Runtime.getAllClasses()
        let selectors: [Selector] = [#selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:completionHandler:)),
                                     #selector(URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)),
                                     #selector(URLSessionTaskDelegate.urlSession(_:task:didCompleteWithError:))]

        // Query all classes that conforms any delegate method
        // We have to do it because there are many classes in the user's source code that conform those methods
        for anyClass in allClasses {
            let methods = Runtime.getAllMethods(from: anyClass)
            var isMatchingFound = false
            for method in methods {
                for selector in selectors {
                    if method_getName(method) == selector {
                        isMatchingFound = true
                        injectIntoDelegate(anyClass: anyClass)
                        break
                    }
                }

                if isMatchingFound {
                    break
                }
            }
        }
    }

    private func injectIntoDelegate(anyClass: AnyClass) {
        print("Start inject into delegate for class \(anyClass)")

        // URLSession
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
            let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            if majorVersion < 9 || majorVersion >= 14 {
                baseResumeClass = URLSessionTask.self
            } else {
                baseResumeClass = NSClassFromString("__NSCFURLSessionTask")
            }
        }

        guard let resumeClass = baseResumeClass else {
            assertionFailure()
            return
        }

        _swizzleURLSessionResumeSelector(baseClass: resumeClass)
    }
}
