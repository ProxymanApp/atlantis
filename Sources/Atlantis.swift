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

    /// Check whether or not Bonjour Service is available in current devices
    private static var isServiceAvailable: Bool = {
        // Require extra config for iOS 14
        if #available(iOS 14, *) {
            return Bundle.main.hasBonjourServices && Bundle.main.hasLocalNetworkUsageDescription
        }
        // Below iOS 14, Bonjour service is always available
        return true
    }()

    /// Determine whether or not the Atlantis is active
    /// It must be wrapped into an atomic for safe-threads
    private static var isEnabled = Atomic<Bool>(false)

    // MARK: - Init

    private override init() {
        transporter = NetServiceTransport()
        super.init()
        injector.delegate = self
        safetyCheck()
    }
    
    // MARK: - Public

    /// Build version of Atlantis
    /// It's essential for Proxyman to known if it's compatible with this version
    /// Instead of receving the number from the info.plist, we should hardcode here because the info file doesn't exist in SPM
    public static let buildVersion: String = "1.1.0"

    /// Start Swizzle all network functions and monitoring the traffic
    /// It also starts looking Bonjour network from Proxyman app
    public class func start(port: UInt16 = 10909) {
        let configuration = Configuration.default(port: port)

        // don't start the service if it's unavailable
        guard Atlantis.isServiceAvailable else {
            // init to call the safe-check
            _ = Atlantis.shared
            return
        }

        guard !isEnabled.value else { return }
        isEnabled.mutate { $0 = true }
        Atlantis.shared.configuration = configuration
        Atlantis.shared.transporter.start(configuration)
        Atlantis.shared.injector.injectAllNetworkClasses()
    }

    /// Stop monitoring
    public class func stop() {
        guard isEnabled.value else { return }
        isEnabled.mutate { $0 = false }
        Atlantis.shared.transporter.stop()
    }
}

// MARK: - Private

extension Atlantis {

    private func safetyCheck() {
        if Atlantis.isServiceAvailable {
            print("---------------------------------------------------------------------------------")
            print("---------- 🧊 Atlantis is running (version \(Bundle(for: Atlantis.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"))")
            print("---------- Github: https://github.com/ProxymanApp/atlantis")
            print("---------------------------------------------------------------------------------")
        }

        // Check required config for Local Network in the main app's info.plist
        // Ref: https://developer.apple.com/news/?id=0oi77447
        // Only for iOS 14
        if #available(iOS 14, *) {
            var instruction: [String] = []
            if !Bundle.main.hasLocalNetworkUsageDescription {
                let config = """
                <key>NSLocalNetworkUsageDescription</key>
                <string>Atlantis would use Bonjour Service to discover Proxyman app from your local network.</string>
                """
                instruction.append(config)
            }
            if !Bundle.main.hasBonjourServices {
                let config = """
                <key>NSBonjourServices</key>
                <array>
                    <string>_Proxyman._tcp</string>
                </array>
                """
                instruction.append(config)
            }
            if !instruction.isEmpty {
                let message = """
                ---------------------------------------------------------------------------------
                --------- [Atlantis] MISSING REQUIRED CONFIG from Info.plist for iOS 14+ --------
                ---------------------------------------------------------------------------------
                Read more at: https://docs.proxyman.io/atlantis/atlantis-for-ios
                Please add the following config to your MainApp's Info.plist

                \(instruction.joined(separator: "\n"))

                """
                print(message)
            }
        }
    }

    private func getPackage(_ taskOrConnection: AnyObject) -> TrafficPackage? {
        // This method should be called from our queue

        // Receive package from the cache
        let id = PackageIdentifier.getID(taskOrConnection: taskOrConnection)
        if let package = packages[id] {
            return package
        }

        // If not found, just generate and cache
        switch taskOrConnection {
        case let task as URLSessionTask:
            guard let package = TrafficPackage.buildRequest(sessionTask: task, id: id) else {
                assertionFailure("Should build package from URLSessionTask")
                return nil
            }
            packages[id] = package
            return package
        case let connection as NSURLConnection:
            guard let package = TrafficPackage.buildRequest(connection: connection, id: id) else {
                assertionFailure("Should build package from NSURLConnection")
                return nil
            }
            packages[id] = package
            return package
        default:
            assertionFailure("Do not support new Type \(String(describing: taskOrConnection.className))")
        }
        return nil
    }
}

// MARK: - Injection Methods

extension Atlantis: InjectorDelegate {

    func injectorSessionDidCallResume(task: URLSessionTask) {
        // Since it's not possible to revert the Method Swizzling change
        // We use isEnable instead
        guard Atlantis.isEnabled.value else { return }
        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            // Cache
            _ = strongSelf.getPackage(task)
        }
    }

    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        guard Atlantis.isEnabled.value else { return }
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(dataTask)
            package?.updateResponse(response)
        }
    }

    func injectorSessionDidReceiveData(dataTask: URLSessionDataTask, data: Data) {
        guard Atlantis.isEnabled.value else { return }
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(dataTask)
            package?.append(data)
        }
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: Error?) {
        handleDidFinish(task, error: error)
    }

    func injectorConnectionDidReceive(connection: NSURLConnection, response: URLResponse) {
        guard Atlantis.isEnabled.value else { return }
        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            // Cache
            let package = strongSelf.getPackage(connection)
            package?.updateResponse(response)
        }
    }

    func injectorConnectionDidReceive(connection: NSURLConnection, data: Data) {
        guard Atlantis.isEnabled.value else { return }
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let package = strongSelf.getPackage(connection)
            package?.append(data)
        }
    }

    func injectorConnectionDidFailWithError(connection: NSURLConnection, error: Error) {
        handleDidFinish(connection, error: error)
    }

    func injectorConnectionDidFinishLoading(connection: NSURLConnection) {
        handleDidFinish(connection, error: nil)
    }
}

// MARK: - Private

extension Atlantis {

    private func handleDidFinish(_ taskOrConnection: AnyObject, error: Error?) {
        guard Atlantis.isEnabled.value else { return }
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            guard let package = strongSelf.getPackage(taskOrConnection) else {
                return
            }

            // All done
            package.updateDidComplete(error)

            // At this time, the package has all the data
            // It's time to send it
            let message = Message.buildTrafficMessage(id: strongSelf.configuration.id, item: package)
            strongSelf.transporter.send(package: message)

            // Then remove it from our cache
            strongSelf.packages.removeValue(forKey: package.id)
        }
    }
}

// MARK: - Helper

extension Bundle {

    var hasLocalNetworkUsageDescription: Bool {
        return Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String != nil
    }

    var hasBonjourServices: Bool {
        guard let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String],
              let proxymanService = services.first,
              proxymanService == NetServiceTransport.Constants.netServiceType else { return false }
        return true
    }
}
