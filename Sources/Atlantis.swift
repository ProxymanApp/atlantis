//
//  Atlantis.swift
//  atlantis
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import ObjectiveC

public protocol AtlantisDelegate: AnyObject {

    func atlantisDidHaveNewPackage(_ package: TrafficPackage)
}

/// The main class of Atlantis
/// Responsible to swizzle certain functions from URLSession
/// to capture the network and send to Proxyman app via Bonjour Service
public final class Atlantis: NSObject {

    static let shared = Atlantis()

    // MARK: - Components

    private weak var delegate: AtlantisDelegate?
    private let transporter: Transporter
    private var injector: Injector = NetworkInjector()
    private(set) var configuration: Configuration = Configuration.default()
    private var packages: [String: TrafficPackage] = [:]
    private lazy var waitingWebsocketPackages: [String: [TrafficPackage]] = [:]
    private let queue = DispatchQueue(label: "com.proxyman.atlantis")

    // MARK: - Variables

    /// Check whether or not Bonjour Service is available in current devices
    private static var isServiceAvailable: Bool = {

        #if os(iOS)

        // on iOS Swift Playgroud, no need to add configs to Info.plist
        if Atlantis.shared.isRunningOniOSPlayground {
            return true
        }

        // Require extra config for iOS 14
        if #available(iOS 14, *) {
            return Bundle.main.hasBonjourServices && Bundle.main.hasLocalNetworkUsageDescription
        }
        #endif
        // Below iOS 14, Bonjour service is always available
        return true
    }()

    /// Determine whether or not the Atlantis is active
    /// It must be wrapped into an atomic for safe-threads
    private static var isEnabled = Atomic<Bool>(false)

    /// Determine whether or not the transport layer (e.g. Bonjour service) is enabled
    /// If it's enabled, it will send the traffic to Proxyman macOS app
    private var isEnabledTransportLayer = true

    /// Determine if Atlantis is running on Swift Playground
    /// If it's enabled, Atlantis will bypass some safety checks
    private var isRunningOniOSPlayground = false

    // MARK: - Init

    private override init() {
        transporter = NetServiceTransport()
        super.init()
        injector.delegate = self
    }
    
    // MARK: - Public

    /// Build version of Atlantis
    /// It's essential for Proxyman to known if it's compatible with this version
    /// Instead of receving the number from the info.plist, we should hardcode here because the info file doesn't exist in SPM
    public static let buildVersion: String = "1.17.0"

    /// Start Swizzle all network functions and monitoring the traffic
    /// It also starts looking Bonjour network from Proxyman app.
    /// If hostName is nil, Atlantis will find all Proxyman apps in the network. It's useful if we have only one machine for personal usage.
    /// If hostName is not nil, Atlantis will try to connect to particular mac machine. It's useful if you have multiple Proxyman.
    /// - Parameter hostName: Host name of Mac machine. You can find your current Host Name in Proxyman -> Certificate -> Install on iOS -> By Atlantis -> Show Start Atlantis
    @objc public class func start(hostName: String? = nil) {
        let configuration = Configuration.default(hostName: hostName)

        //
        if Atlantis.shared.isEnabledTransportLayer {

            // Check if Bonjour and required info's key are available
            Atlantis.shared.safetyCheck()

            // don't start the service if it's unavailable
            guard Atlantis.isServiceAvailable else {
                return
            }
        }

        // 
        guard !isEnabled.value else { return }
        isEnabled.mutate { $0 = true }

        // Enable the injector
        Atlantis.shared.configuration = configuration
        Atlantis.shared.injector.injectAllNetworkClasses()

        // Start transport layer if need
        if Atlantis.shared.isEnabledTransportLayer {
            Atlantis.shared.transporter.start(configuration)
        }
    }

    /// Stop monitoring
    @objc public class func stop() {
        guard isEnabled.value else { return }
        isEnabled.mutate { $0 = false }
        if Atlantis.shared.isEnabledTransportLayer {
            Atlantis.shared.transporter.stop()
        }
    }

    /// Enable Transport Layer (e.g. Bonjour)
    public class func setEnableTransportLayer(_ isEnabled: Bool) {
        Atlantis.shared.isEnabledTransportLayer = isEnabled
    }

    /// Enable Swift Playground mode
    public class func setIsRunningOniOSPlayground(_ isEnabled: Bool) {
        Atlantis.shared.isRunningOniOSPlayground = isEnabled
    }

    /// Set delegate to observe the traffic
    public class func setDelegate(_ delegate: AtlantisDelegate) {
        Atlantis.shared.delegate = delegate
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

        // Don't need to check configs on Info.plist
        if Atlantis.shared.isRunningOniOSPlayground {
            print("---------- Running on Swift Playground Mode")
            print("If you get the SSL Error, please follow this code: https://gist.github.com/NghiaTranUIT/275c8da5068d506869a21bd16da27094")
            return
        }

        // For iOS
        #if os(iOS)

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
                --------- ⚠️ [Atlantis] MISSING REQUIRED CONFIG from Info.plist for iOS 14+ --------
                ---------------------------------------------------------------------------------
                Read more at: https://docs.proxyman.io/atlantis/atlantis-for-ios
                Please add the following config to your MainApp's Info.plist

                \(instruction.joined(separator: "\n"))

                """
                print(message)
            }
        }
        #endif
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
            package?.appendResponseData(data)
        }
    }

    func injectorSessionDidComplete(task: URLSessionTask, error: Error?) {
        handleDidFinish(task, error: error)
    }

    func injectorSessionDidUpload(task: URLSessionTask, request: NSURLRequest, data: Data?) {
        queue.sync {
            // Since it's not possible to revert the Method Swizzling change
            // We use isEnable instead
            guard Atlantis.isEnabled.value else { return }

            // Generate new request and add the data
            let package = getPackage(task)
            if let data = data {
                package?.appendRequestData(data)
            }
        }
    }
}

// MARK: - Websocket

extension Atlantis {

    func injectorSessionWebSocketDidSendPingPong(task: URLSessionTask) {
        let message = URLSessionWebSocketTask.Message.string("ping")
        sendWebSocketMessage(task: task, messageType: .pingPong, message: message)
    }

    func injectorSessionWebSocketDidReceive(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        sendWebSocketMessage(task: task, messageType: .receive, message: message)
    }

    func injectorSessionWebSocketDidSendMessage(task: URLSessionTask, message: URLSessionWebSocketTask.Message) {
        sendWebSocketMessage(task: task, messageType: .send, message: message)
    }

    private func sendWebSocketMessage(task: URLSessionTask, messageType: WebsocketMessagePackage.MessageType, message: URLSessionWebSocketTask.Message) {
        queue.sync {
            // Since it's not possible to revert the Method Swizzling change
            // We use isEnable instead
            guard Atlantis.isEnabled.value else { return }
            prepareAndSendWSMessage(task: task) { (id) -> WebsocketMessagePackage? in
                guard let atlantisMessage = WebsocketMessagePackage.Message(message: message) else {
                    return nil
                }
                return WebsocketMessagePackage(id: id, message: atlantisMessage, messageType: messageType)
            }
        }
    }

    func injectorSessionWebSocketDidSendCancelWithReason(task: URLSessionTask, closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        queue.sync {
            // Since it's not possible to revert the Method Swizzling change
            // We use isEnable instead
            guard Atlantis.isEnabled.value else { return }
            prepareAndSendWSMessage(task: task) { (id) -> WebsocketMessagePackage? in
                return WebsocketMessagePackage(id: id, closeCode: closeCode.rawValue, reason: reason)
            }

            // Remove after the WS connection is closed
            let id = PackageIdentifier.getID(taskOrConnection: task)
            packages.removeValue(forKey: id)
        }
    }

    private func prepareAndSendWSMessage(task: URLSessionTask, wsPackageBuilder: (String) -> WebsocketMessagePackage?) {
        // Get the ID
        let id = PackageIdentifier.getID(taskOrConnection: task)

        // The value should be available
        if let package = packages[id] {

            // Build a package
            guard let wsPackage = wsPackageBuilder(id) else {
                print("[Atlantis][Error] Skipping sending WS Packages!! Please contact Proxyman Team.")
                return
            }

            // It's important to set a message with a WS package
            package.setWebsocketMessagePackage(package: wsPackage)

            // Sending via Bonjour service
            startSendingWebsocketMessage(package)
        } else {
            assertionFailure("Something went wrong! Should find a previous WS Package! Please contact the author!")
        }
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
            switch package.packageType {
            case .http:
                packages.removeValue(forKey: package.id)
            case .websocket:
                // Don't remove the WS traffic
                // Keep it in the packages, so we can send the WS Message
                // Only remove the we receive the Close message

                // Sending all waiting WS
                attemptSendingAllWaitingWSPackages(id: package.id)
                break
            }
        }
    }

    func startSendingMessage(package: TrafficPackage) {
        // Notify the delegate
        if let delegate = delegate {

            // Should be called from the Main thread since the Traffic is running on different threads
            DispatchQueue.main.async {
                delegate.atlantisDidHaveNewPackage(package)
            }
        }

        // Send to Proxyman app
        guard isEnabledTransportLayer else {
            return
        }

        let message = Message.buildTrafficMessage(id: configuration.id, item: package)
        transporter.send(package: message)
    }

    func startSendingWebsocketMessage(_ package: TrafficPackage) {
        let id = package.id

        // If the response of WS is nil
        // It means that the WS is not finished yet,
        // We don't send it, we put it in the waiting queue
        if package.response == nil {
            var waitingList = waitingWebsocketPackages[id] ?? []
            waitingList.append(package)
            waitingWebsocketPackages[id] = waitingList
            return
        }

        // Sending all waiting WS if need
        attemptSendingAllWaitingWSPackages(id: id)

        // Send the current one
        let message = Message.buildWebSocketMessage(id: configuration.id, item: package)
        transporter.send(package: message)
    }

    private func attemptSendingAllWaitingWSPackages(id: String) {
        guard !waitingWebsocketPackages.isEmpty else {
            return
        }
        guard let waitingList = waitingWebsocketPackages[id] else {
            return
        }

        // Send all waiting WS Message
        waitingList.forEach { item in
            let message = Message.buildWebSocketMessage(id: configuration.id, item: item)
            transporter.send(package: message)
        }

        // Release the list
        waitingWebsocketPackages[id] = nil
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
