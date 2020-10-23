//
//  Atlantis.swift
//  atlantis
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import ObjectiveC

///
/// Inspire from Flex
/// https://github.com/FLEXTool/FLEX/tree/master/Classes/Network/PonyDebugger
///
/// Use method_setImplementation() instead of method_exchangeImplementations
/// https://blog.newrelic.com/engineering/right-way-to-swizzle/
///
public final class Atlantis: NSObject {

    private struct Constants {
        static let isEnabledNetworkInjector = "isEnabledNetworkInjector"
    }

    // MARK: - Variables

    /// Determine whether or not Atlantis start intercepting
    /// When it's enabled, Atlantis starts swizzling all available network methods
    public static var isEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.isEnabledNetworkInjector)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.isEnabledNetworkInjector)
            if newValue {
                self.injectAllNetworkClasses()
            }
        }
    }

    // MARK: - Components

    static private(set) var transporter: Transporter = NetServiceTransport()

    // MARK: - Public config


    /// Config different type of transporter
    /// It might be NSNetService or classess that conforms Transporter protocol
    /// - Parameter transporter: Transporter
    class func setTransporter(_ transporter: Transporter) {
        self.transporter = transporter
    }
}

// MARK: - Injection Methods

extension Atlantis {

    private class func injectAllNetworkClasses() {
        // Make sure we swizzle *ONCE*
        DispatchQueue.once {
            injectURLSessionResume()
        }
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

        _swizzleResumeSelector(baseClass: resumeClass)
    }

    private class func _swizzleResumeSelector(baseClass: AnyClass) {
        // Prepare
        let selector = NSSelectorFromString("resume")
        guard let method = class_getInstanceMethod(baseClass, selector),
            baseClass.instancesRespond(to: selector) else {
            assertionFailure()
            return
        }

        // Get original method to call later
        let originalIMP = method_getImplementation(method)

        // swizzle the original with the new one and start intercepting the content
        let swizzleIMP = imp_implementationWithBlock({(slf: URLSessionTask) -> Void in

            // Compose and send
            if let package = PrimaryPackage.buildRequest(dataTask: slf) {
                self.transporter.send(package: package)
            }

            // Make sure the original method is called
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (URLSessionTask, Selector) -> Void).self)
            oldIMP(slf, selector)
            } as @convention(block) (URLSessionTask) -> Void)

        //
        method_setImplementation(method, swizzleIMP)
    }
}
