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

    private static let shared = Atlantis()

    private struct Constants {
        static let isEnabledNetworkInjector = "isEnabledNetworkInjector"
    }

    // MARK: - Class variables

    /// Determine whether or not Atlantis start intercepting
    /// When it's enabled, Atlantis starts swizzling all available network methods
    public static var isEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.isEnabledNetworkInjector)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.isEnabledNetworkInjector)
            if newValue {
                Atlantis.shared.injector.injectAllNetworkClasses()
            }
        }
    }

    // MARK: - Components

    private(set) var transporter: Transporter = NetServiceTransport()
    private(set) var injector: Injector = NetworkInjector()

    // MARK: - Init

    private override init() {
        super.init()
        injector.delegate = self
    }
    
    // MARK: - Public config

    /// Config different type of transporter
    /// It might be NSNetService or classess that conforms Transporter protocol
    /// - Parameter transporter: Transporter
    public class func setTransporter(_ transporter: Transporter) {
        Atlantis.shared.transporter = transporter
    }
}

// MARK: - Injection Methods

extension Atlantis: InjectorDelegate {

    func injectorDidReceiveResume(sessionTask: URLSessionTask) {
        guard let package = PrimaryPackage.buildRequest(sessionTask: sessionTask) else {
            return
        }
        self.transporter.send(package: package)
    }
}
