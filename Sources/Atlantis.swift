//
//  Atlantis.swift
//  atlantis
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import ObjectiveC

/// The main class of Atlantis
/// Responsible to swizzle certain functions from URLSession and URLConnection
/// to capture the network and send to Proxyman app via Bonjour Service
public final class Atlantis: NSObject {

    private static let shared = Atlantis()

    // MARK: - Components

    private let transporter: Transporter
    private var injector: Injector = NetworkInjector()
    private(set) var configuration: Configuration = Configuration.default()
    private var packages: [String: TrafficPackage] = [:]
    private let queue = DispatchQueue(label: "com.proxyman.atlantis")

    // MARK: - Variables

    private static var isEnabled: Bool = false {
        didSet {
            guard self.isEnabled != oldValue else { return }
            if isEnabled {

            } else {
                Atlantis.shared.transporter.stop()
            }
        }
    }

    // MARK: - Init

    private override init() {
        transporter = NetServiceTransport()
        super.init()
        injector.delegate = self
        safetyCheck()
    }
    
    // MARK: - Public

    public class func start(_ configuration: Configuration = Configuration.default()) {
        guard !isEnabled else { return }
        self.isEnabled = true
        Atlantis.shared.configuration = configuration
        Atlantis.shared.transporter.start(configuration)
        Atlantis.shared.injector.injectAllNetworkClasses()
    }

    public class func stop() {
        guard isEnabled else { return }
        self.isEnabled = false
        Atlantis.shared.transporter.stop()
    }
}

// MARK: - Private

extension Atlantis {

    private func safetyCheck() {
        print("------------------------------------------------------------")
        print("---------- 🧊 Atlantis is running (version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"))")
        print("---------- If you found any problems, please report at: https://github.com/ProxymanApp/atlantis")
        print("------------------------------------------------------------")
    }

    private func getPackage(_ task: URLSessionTask) -> TrafficPackage? {
        // This method should be called from our queue

        // Receive package from the cache
        let id = PackageIdentifier.getID(task: task)
        if let package = packages[id] {
            return package
        }

        // If not found, just generate and cache
        guard let package = TrafficPackage.buildRequest(sessionTask: task, id: id) else {
            assertionFailure("Should build package from Request")
            return nil
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
            print("Did Add new package, count = \(strongSelf.packages.count)")
        }
    }

    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(dataTask)
            package?.updateResponse(response)
        }
    }

    func injectorSessionDidReceiveData(dataTask: URLSessionDataTask, data: Data) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(dataTask)
            package?.append(data)
        }
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: Error?) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            guard let package = strongSelf.getPackage(task) else {
                assertionFailure("Internal error. We should have Package")
                return
            }
            package.updateError(error)

            // At this time, the package has all the data
            // It's time to send it
            let message = Message.buildTrafficMessage(id: strongSelf.configuration.id, item: package)
            strongSelf.transporter.send(package: message)

            // Then remove it from our cache
            strongSelf.packages.removeValue(forKey: package.id)

            print("------------- Did Complete. Count = \(strongSelf.packages.count)")
        }
    }
}
