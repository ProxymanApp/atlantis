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

    // MARK: - Class variables

    /// Determine whether or not Atlantis start intercepting
    /// When it's enabled, Atlantis starts swizzling all available network methods
    public static var isEnabled: Bool = false {
        didSet {
            guard self.isEnabled != oldValue else { return }
            Atlantis.shared.transporter.start()
            Atlantis.shared.injector.injectAllNetworkClasses()
        }
    }

    // MARK: - Components

    private(set) lazy var transporter: Transporter = {
        return NetServiceTransport(configuration: configuration)
    }()
    private(set) var injector: Injector = NetworkInjector()
    private(set) var configuration: Configuration = Configuration.default()

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

    public class func setConfiguration(_ config: Configuration) {
        Atlantis.shared.configuration = config
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
