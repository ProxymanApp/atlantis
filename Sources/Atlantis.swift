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
    private var packages: [String: Package] = [:]
    private let queue = DispatchQueue(label: "com.proxyman.atlantis")

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

// MARK: - Private

extension Atlantis {

    private func getPackage(_ task: URLSessionTask) -> Package {
        // This method should be called from our queue

        // Receive package from the cache
        let id = PackageIdentifier.getID(task: task)
        if let package = packages[id] {
            return package
        }

        // If not found, just generate and cache
        guard let package = PrimaryPackage.buildRequest(sessionTask: task, id: id) else {
            fatalError("Should build package from Request")
        }
        packages[id] = package
        return package
    }
}

// MARK: - Injection Methods

extension Atlantis: InjectorDelegate {

    func injectorSessionDidCallResume(task: URLSessionTask) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            // Cache
            _ = strongSelf.getPackage(task)
        }
    }

    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(dataTask)
            package.updateResponse(response)
        }
    }


    func injectorSessionDidReceiveData(dataTask: URLSessionDataTask, data: Data) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(dataTask)
            package.append(data)
        }
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: Error?) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(task)
            package.updateError(error)

            // At this time, the package has all the data
            // It's time to send it
            strongSelf.transporter.send(package: package)

            // Then remove it from our cache
            strongSelf.packages.removeValue(forKey: package.id)
        }
    }
}
