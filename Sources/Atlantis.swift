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

    static let shared = Atlantis()

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
    public static let buildVersion: String = "1.4.3"

    /// Start Swizzle all network functions and monitoring the traffic
    /// It also starts looking Bonjour network from Proxyman app.
    /// If hostName is nil, Atlantis will find all Proxyman apps in the network. It's useful if we have only one machine for personal use.
    /// If hostName is not nil, Atlantis will try to connect to particular mac machine. It's useful if you have multiple Proxyman.
    /// - Parameter hostName: Host name of Mac machine. You can find your current Host Name in Proxyman -> Certificate -> Install on iOS -> By Atlantis -> Show Start Atlantis
    public class func start(hostName: String? = nil) {
        let configuration = Configuration.default(hostName: hostName)

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
        // Use sync to prevent task.currentRequest.httpBody is nil
        // If we use async, sometime the httpbody is released -> Atlantis could get the Request's body
        // It's safe to use sync here because URL has their own background queue
        queue.sync {
            // Since it's not possible to revert the Method Swizzling change
            // We use isEnable instead
            guard Atlantis.isEnabled.value else { return }

            // Cache
            _ = getPackage(task)
        }
    }

    func injectorSessionDidReceiveResponse(dataTask: URLSessionTask, response: URLResponse) {
        queue.sync {
            guard Atlantis.isEnabled.value else { return }
            let package = getPackage(dataTask)
            package?.updateResponse(response)
        }
    }

    func injectorSessionDidReceiveData(dataTask: URLSessionTask, data: Data) {
        queue.sync {
            guard Atlantis.isEnabled.value else { return }
            let package = getPackage(dataTask)
            package?.append(data)
        }
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: Error?) {
        handleDidFinish(task, error: error)
    }

    func injectorConnectionDidReceive(connection: NSURLConnection, response: URLResponse) {
        queue.sync {
            guard Atlantis.isEnabled.value else { return }

            // Cache
            let package = getPackage(connection)
            package?.updateResponse(response)
        }
    }

    func injectorConnectionDidReceive(connection: NSURLConnection, data: Data) {
        queue.sync {
            guard Atlantis.isEnabled.value else { return }
            let package = getPackage(connection)
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
        queue.sync {
            guard Atlantis.isEnabled.value else { return }
            guard let package = getPackage(taskOrConnection) else {
                return
            }

            // All done
            package.updateDidComplete(error)

            // At this time, the package has all the data
            // It's time to send it
            startSendingMessage(package: package)

            // Then remove it from our cache
            packages.removeValue(forKey: package.id)
        }
    }

    internal func startSendingMessage(package: TrafficPackage) {
        let message = Message.buildTrafficMessage(id: configuration.id, item: package)
        transporter.send(package: message)
    }
}

// MARK: - Helper

extension Bundle {

    var hasLocalNetworkUsageDescription: Bool {
        return Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String != nil
    }

    var hasBonjourServices: Bool {
        guard let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String] else {
            return false
        }
        // It works fine if the app has many Bonjour services
        return services.contains(where: { $0 == NetServiceTransport.Constants.netServiceType })
    }
}
