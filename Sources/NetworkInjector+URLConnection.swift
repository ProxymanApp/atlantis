//
//  NetworkInjector+URLConnection.swift
//  atlantis
//
//  Created by Nghia Tran on 10/24/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

extension NetworkInjector {

    /// https://developer.apple.com/documentation/foundation/nsurlconnectiondatadelegate/1407728-connection?language=objc
    func _swizzleConnectionDidReceiveResponse(anyClass: AnyClass) {
        //
        // Have to explicitly tell the compiler which func
        // because there are two different objc methods, but different argments
        // It causes the bug: Ambiguous use of 'connection(_:didReceive:)'
        //
        let selector : Selector = #selector((NSURLConnectionDataDelegate.connection(_:didReceive:)!)
            as (NSURLConnectionDataDelegate) -> (NSURLConnection, URLResponse) -> Void)

        guard let method = class_getInstanceMethod(anyClass, selector),
            anyClass.instancesRespond(to: selector) else {
            return
        }

        // Get original method to call later
        let originalIMP = method_getImplementation(method)

        // swizzle the original with the new one and start intercepting the content
        let swizzleIMP = imp_implementationWithBlock({(slf: NSURLConnectionDataDelegate, connection: NSURLConnection, response: URLResponse) -> Void in

            // Notify
            print("------")
//            self?.delegate?.injectorSessionDidReceiveResponse(dataTask: dataTask, response: response)

            // Make sure the original method is called
            let oldIMP = unsafeBitCast(originalIMP, to: (@convention(c) (NSURLConnectionDataDelegate, Selector, NSURLConnection, URLResponse) -> Void).self)
            oldIMP(slf, selector, connection, response)
            } as @convention(block) (NSURLConnectionDataDelegate, NSURLConnection, URLResponse) -> Void)

        //
        method_setImplementation(method, swizzleIMP)
    }
}
