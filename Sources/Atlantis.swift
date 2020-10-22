//
//  Atlantis.swift
//  atlantis
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import ObjectiveC

/// Inspire from Flex
/// https://github.com/FLEXTool/FLEX/tree/master/Classes/Network/PonyDebugger
final class Atlantis: NSObject {

    private struct Constants {
        static let isEnabledNetworkInjector = "isEnabledNetworkInjector"
    }

    // MARK: - Variables

    static var isEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.isEnabledNetworkInjector)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.isEnabledNetworkInjector)
            if newValue {
                injectAllNetworkClasses()
            }
        }
    }
}

// MARK: - Injection Methods

extension Atlantis {

    private class func injectAllNetworkClasses() {
        injectURLSessionResume()
    }
}

// MARK: - URLSession

extension Atlantis {

    private class func injectURLSessionResume() {
        // In iOS 7 resume lives in __NSCFLocalSessionTask
        // In iOS 8 resume lives in NSURLSessionTask
        // In iOS 9 resume lives in __NSCFURLSessionTask
        // In iOS 14 resume lives in NSURLSessionTask
        var baseResumeClass: AnyClass? = nil;
        if ProcessInfo.processInfo.responds(to: #selector(getter: ProcessInfo.operatingSystemVersion)) {
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

        _swizzleResumeSelector(baseClass: resumeClass)
    }

    private class func _swizzleResumeSelector(baseClass: AnyClass) {

        let selector = NSSelectorFromString("resume")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            assertionFailure()
            return
        }

        let originalIMP = method_getImplementation(method)
        let swizzleIMP = imp_implementationWithBlock({ (self: URLSessionTask) -> Void in
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSessionTask, Selector) -> Void).self)
            oldIMP(self, selector)
            } as @convention(block) (URLSessionTask) -> Void)
        method_setImplementation(method, swizzleIMP)
    }
}
