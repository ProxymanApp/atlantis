//
//  Transporter.swift
//  atlantis-iOS
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import Network

#if os(iOS)
import UIKit
#endif

protocol Transporter {

    func start(_ config: Configuration)
    func stop()
    func send(package: Serializable)
}

protocol Serializable {

    func toData() -> Data?
    var retentionPriority: TransportRetentionPriority { get }
    var replacementWhenDropped: Serializable? { get }
}

enum TransportRetentionPriority {
    case essential
    case payload
}

extension Serializable {

    var retentionPriority: TransportRetentionPriority {
        return .essential
    }

    var replacementWhenDropped: Serializable? {
        return nil
    }

    func toCompressedData() -> Data? {
        guard let rawData = self.toData() else { return nil }

        // Compress data by gzip
        // Fallback to raw data if it's unsuccess
        return rawData.gzip() ?? rawData
    }
}

final class NetServiceTransport: NSObject {

    private struct PendingFrame {
        let data: Data
        let retentionPriority: TransportRetentionPriority
        let replacementData: Data?
    }

    struct Constants {
        static let netServiceType = "_Proxyman._tcp"
        static let netServiceDomain = ""
        static let directConnectionPort: NWEndpoint.Port = 10909 // Port for direct simulator connection
    }

    // MARK: - Variables

    // For some reason, Stream Task could send a big file
    // https://github.com/ProxymanApp/atlantis/issues/57
    static let MaximumSizePackage = 52428800 // 50Mb

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.netservices") // Serial queue for thread safety
    private let queueKey = DispatchSpecificKey<Void>()
    private var pendingFrames: [PendingFrame] = []
    private var pendingFrameBytes = 0
    private var pendingDropMarker: Data?
    private var isSendingFrame = false
    private var sendGeneration: UInt64 = 0
    private var config: Configuration?

    // Multiple task connection support using NWConnection
    private var connections: [NWConnection] = []

    // Bound queued traffic while retaining lifecycle events ahead of message bodies.
    private let maxPendingItem = 256
    private let maxPendingBytes = 64 * 1024 * 1024

    // Retry mechanism for simulator direct connection
    private var simulatorRetryCount = 0
    private let maxSimulatorRetries = 5

    // MARK: - Init

    override init() {
        super.init()
        queue.setSpecific(key: queueKey, value: ())
        initNotification()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Scheduling a weak async stop while deinitializing can ask Objective-C to form a weak
        // reference to an object which is already being destroyed.
        stopInternal()
    }
}

#if DEBUG
extension NetServiceTransport {
    var pendingBufferStatsForTesting: (count: Int, bytes: Int, hasDropMarker: Bool) {
        return queue.sync {
            (pendingFrames.count, pendingFrameBytes, pendingDropMarker != nil)
        }
    }
}
#endif

// MARK: - Transporter

extension NetServiceTransport: Transporter {

    func start(_ config: Configuration) {
        self.config = config

        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            // Reset all current connections and browser if needed
            strongSelf.stopInternal()

            #if targetEnvironment(simulator)
            // iOS Simulator: Direct TCP connection
            let endpoint = strongSelf.getEndpointForLocalhost()
            
            // Reset retry count before starting
            strongSelf.simulatorRetryCount = 0
            print("⚡️[Atlantis][Simulator] Attempting direct connection to Proxyman app on your Mac... without using Bonjour service (due to macOS 15.4+ issue)")
            let connection = NWConnection(to: endpoint, using: .tcp)
            strongSelf.setupAndStartConnection(connection)

            #else
            // iOS Real Device: Use Bonjour Browsing
            if let hostName = config.hostName {
                print("⚡️[Atlantis] Looking for Proxyman app with name \"\(hostName)\" by using Bonjour service on the local network...")
            } else {
                print("⚡️[Atlantis] Looking for Proxyman app using Bonjour service on the local network...")
            }
            strongSelf.startBrowsing()
            #endif
        }
    }

    func stop() {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            strongSelf.stopInternal()
        }
    }

    func send(package: Serializable) {
        performOnQueue {
            guard let compressedData = package.toCompressedData() else { return }
            let frame = PendingFrame(
                data: compressedData,
                retentionPriority: package.retentionPriority,
                replacementData: package.replacementWhenDropped?.toCompressedData()
            )
            appendToPendingList(frame)
            sendNextPendingFrameIfPossible()
        }
    }

    private func performOnQueue(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            operation()
        } else {
            // Applying the queue limit synchronously avoids an unbounded backlog of dispatch blocks
            // when many streaming messages arrive faster than Network.framework can write them.
            queue.sync(execute: operation)
        }
    }

    private func send(connection: NWConnection, data: Data, completion: (() -> Void)? = nil) {
        guard connection.state == .ready else {
            print("[\(connection.endpoint.debugDescription)] ⚠️ Attempted to send data on a non-ready connection. State: \(connection.state)")
            completion?()
            return
        }

        // Compose a message
        // [1]: the length of the second message. We reserver 8 bytes to store this data
        // [2]: The actual message

        // 1. Send length of the message first
        let headerData = NSMutableData()
        var lengthPackage = UInt64(data.count) // Use UInt64 for length
        headerData.append(&lengthPackage, length: MemoryLayout<UInt64>.size)

        // Send the length header, must use isComplete = false
        connection.send(content: headerData as Data, isComplete: false, completion: .contentProcessed({ error in
            if let error = error {
                print("[\(connection.endpoint.debugDescription)][Error] Error sending frame header: \(error)")
            }
        }))

        // 2. send the actual message
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("[\(connection.endpoint.debugDescription)][Error] Error sending frame content: \(error)")
            }
            completion?()
        }))
    }

    private func appendToPendingList(_ frame: PendingFrame) {
        pendingFrames.append(frame)
        pendingFrameBytes += frame.data.count

        while pendingFrames.count > maxPendingItem || pendingFrameBytes > maxPendingBytes {
            let payloadIndex = pendingFrames.firstIndex { $0.retentionPriority == .payload }
            let removalIndex = payloadIndex ?? pendingFrames.startIndex
            let removedFrame = pendingFrames.remove(at: removalIndex)
            pendingFrameBytes -= removedFrame.data.count

            // Keep one small omission event so Proxyman can explain missing message contents.
            if let replacementData = removedFrame.replacementData {
                pendingDropMarker = replacementData
            }
        }
    }

    private func sendNextPendingFrameIfPossible() {
        guard !isSendingFrame else { return }
        let readyConnections = connections.filter { $0.state == .ready }
        guard !readyConnections.isEmpty else { return }

        let data: Data
        if let dropMarker = pendingDropMarker {
            data = dropMarker
            pendingDropMarker = nil
        } else if !pendingFrames.isEmpty {
            let frame = pendingFrames.removeFirst()
            pendingFrameBytes -= frame.data.count
            data = frame.data
        } else {
            return
        }

        isSendingFrame = true
        let generation = sendGeneration
        let completionGroup = DispatchGroup()
        for connection in readyConnections {
            completionGroup.enter()
            send(connection: connection, data: data) {
                completionGroup.leave()
            }
        }
        completionGroup.notify(queue: queue) { [weak self] in
            guard let self = self, self.sendGeneration == generation else { return }
            self.isSendingFrame = false
            self.sendNextPendingFrameIfPossible()
        }
    }
}

// MARK: - Private Connection & Browsing Logic (on queue)

extension NetServiceTransport {

    private func startBrowsing() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Constants.netServiceType, domain: Constants.netServiceDomain), using: parameters)

        browser.stateUpdateHandler = {[weak self] newState in
            guard let strongSelf = self else { return }
            switch newState {
            case .failed(let error):
                print("[Atlantis][Error] Bonjour Browser failed: \(error). Ensure network permissions and Bonjour service are correct.")
                // Consider implementing retry logic here if desired
                browser.cancel() // Cancel the failed browser
                if strongSelf.browser === browser { // Ensure we are cancelling the current browser
                    strongSelf.browser = nil
                }
            case .ready:
                print("[Atlantis] Bonjour Browser is ready and scanning.")
            case .cancelled:
                print("[Atlantis] Bonjour Browser cancelled.")
                if strongSelf.browser === browser { // Ensure we are cancelling the current browser
                    strongSelf.browser = nil
                }
            case .waiting(let error):

                switch error {
                case .dns(let code):
                    switch Int(code) {
                    case kDNSServiceErr_PolicyDenied:
                        #if targetEnvironment(simulator)
                        print("--------------------------------")
                        print("❌[Atlantis][Error] Bonjour service failed with PolicyDenied (kDNSServiceErr_PolicyDenied). This might be related to a known issue on macOS 15.4+ with iOS Simulators.")
                        print("✅ [Atlantis] Suggested Solutions:")
                        print("[Atlantis] 1. Use Atlantis on a real iOS device.")
                        print("[Atlantis] OR")
                        print("[Atlantis] 2. Don't use Atlantis on iOS Simulator, and use normal Proxy instead. Open Proxyman on macOS -> Certificate menu -> Install certificate on iOS -> Simulators -> Follow guide to set up your iOS Simulator.")
                        print("--------------------------------")
                        print("[Atlantis] Github Issue: https://github.com/ProxymanApp/Proxyman/issues/2294")
                        print("--------------------------------")
                        #else
                        print("--------------------------------")
                        print("[Atlantis][Error] Bonjour service failed with PolicyDenied (kDNSServiceErr_PolicyDenied). This could be due to missing Local Network permission for your app.")
                        print("✅ [Atlantis] Suggested Solutions:")
                        print("[Atlantis] 1. Go to iOS Settings -> Privacy & Security -> Local Network -> Find your app -> Turn ON.")
                        print("[Atlantis] OR")
                        print("[Atlantis] 2. Alternatively, try deleting the app from your device and running it again. Click 'Allow' when system asks for Local Network permission.")
                        print("-------------------------------- ")
                        #endif
                    default:
                        print(code)
                    }
                case .posix:
                    break
                case .tls:
                    break
                @unknown default:
                    break
                }
            case .setup:
                break
            @unknown default:
                break
            }
        }

        browser.browseResultsChangedHandler = {[weak self] results, changes in
            guard let strongSelf = self else { return }
            for change in changes {
                switch change {
                case .added(let result):
                    print("[Atlantis] Bonjour discovered: \(NetServiceTransport.hostname(from: result.endpoint) ?? "Unknown")")
                    strongSelf.connectToEndpointIfNeeded(result.endpoint)
                case .removed(let result):
                    print("[Atlantis] Bonjour removed: \(result.endpoint.debugDescription)")
                    strongSelf.disconnectFromEndpoint(result.endpoint)
                case .changed(_, let newResult, _): // Simplified handling
                    // Re-evaluate connection on change
                    print("[Atlantis] Bonjour changed: \(newResult.endpoint.debugDescription)")
                    strongSelf.connectToEndpointIfNeeded(newResult.endpoint)
                default:
                    break
                }
            }
        }

        self.browser = browser
        browser.start(queue: self.queue)
    }

    private func connectToEndpointIfNeeded(_ endpoint: NWEndpoint) {
        // Prevent duplicate connections to the same endpoint
        guard !connections.contains(where: { $0.endpoint == endpoint }) else {
            print("[Atlantis] Already connected or connecting to \(endpoint.debugDescription). Skipping.")
            return
        }

        // Check if we should connect based on hostname configuration
        guard shouldConnectToEndpoint(endpoint) else {
            return // Log message is printed inside shouldConnectToEndpoint
        }

        print("[Atlantis] ✅ Attempting to connect to \(endpoint.debugDescription)")
        let connection = NWConnection(to: endpoint, using: .tcp)
        setupAndStartConnection(connection)
    }

    private func disconnectFromEndpoint(_ endpoint: NWEndpoint) {
        let connectionsToRemove = connections.filter { $0.endpoint == endpoint }
        connectionsToRemove.forEach { $0.cancel() }
        connections.removeAll { $0.endpoint == endpoint }
        if !connectionsToRemove.isEmpty {
            print("[Atlantis] Disconnected from \(endpoint.debugDescription)")
        }
    }

    private func setupAndStartConnection(_ connection: NWConnection) {
        connections.append(connection)
        setupConnectionStateHandler(connection)
        connection.start(queue: queue)
    }

    private func setupConnectionStateHandler(_ connection: NWConnection) {
        connection.stateUpdateHandler = {[weak self] (newState) in
            guard let strongSelf = self else { return }

            let endpointDesc = connection.endpoint.debugDescription // Capture for logging

            switch newState {
            case .setup:
                break
            case .preparing:
                break
            case .ready:
                print("[\(endpointDesc)] ✅ Connection established.")
                // Send initial connection info and resume the backpressured frame queue.
                #if targetEnvironment(simulator)
                // Reset retry counter on successful simulator connection
                strongSelf.simulatorRetryCount = 0
                #endif
                strongSelf.sendConnectionPackage(connection: connection)
                strongSelf.sendNextPendingFrameIfPossible()
            case .waiting(let error):
                #if targetEnvironment(simulator)
                // For simulator, attempt to retry the connection after a delay
                // instead of just printing the waiting state.

                // Cancel the current connection attempt
                connection.cancel()

                // Remove the connection immediately to allow retry
                if let index = strongSelf.connections.firstIndex(where: { $0 === connection }) {
                    strongSelf.connections.remove(at: index)
                }

                // Check retry limit
                if strongSelf.simulatorRetryCount < strongSelf.maxSimulatorRetries {
                    strongSelf.simulatorRetryCount += 1
                    let currentRetry = strongSelf.simulatorRetryCount
                    let maxRetries = strongSelf.maxSimulatorRetries
                    print("Could not found Proxyman app on your Mac.")
                    print("🔄 Attempting re-connect (\(currentRetry)/\(maxRetries)) to Proxyman app in 15 seconds... Make sure Proxyman app is running on your Mac.")

                    // Schedule a retry
                    strongSelf.queue.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                        guard let strongSelf = self else { return }
                        // Re-attempt connection using the original logic
                        let endpoint = strongSelf.getEndpointForLocalhost()
                        let newConnection = NWConnection(to: endpoint, using: .tcp)
                        print("[Atlantis][Simulator] Retry #\(currentRetry): Creating new connection to \(endpoint.debugDescription)")
                        strongSelf.setupAndStartConnection(newConnection) // Start the *new* connection attempt
                    }
                } else {
                    print("❌ [Atlantis][Simulator] Maximum retry limit (\(strongSelf.maxSimulatorRetries)) reached. Stopping connection attempts.")
                }
                #else
                print("[\(endpointDesc)] ⚠️ Connection waiting: \(error).")
                #endif
            case .failed(let error):
                print("[\(endpointDesc)] ❌ Connection failed: \(error).")
                // Remove the failed connection
                strongSelf.connections.removeAll { $0 === connection }
            case .cancelled:
                // Remove the cancelled connection
                strongSelf.connections.removeAll { $0 === connection }
            @unknown default:
                print("[\(endpointDesc)] Unknown connection state.")
                break
            }
        }
    }

    private func sendConnectionPackage(connection: NWConnection) {
        guard let config = config else {
            print("[\(connection.endpoint.debugDescription)][Error] Missing configuration, cannot send connection package.")
            return
        }

        // Create and send the initial connection message
        let connectionMessage = Message.buildConnectionMessage(id: config.id, item: ConnectionPackage(config: config))
        guard let data = connectionMessage.toCompressedData() else {
            print("[\(connection.endpoint.debugDescription)][Error] Could not create connection package data.")
            return
        }
        send(connection: connection, data: data)
    }

    // MARK: - Helper Methods

    // Check if connection should proceed based on configured hostname
    private func shouldConnectToEndpoint(_ endpoint: NWEndpoint) -> Bool {
        // If no specific hostname is configured, always allow connection
        guard let requiredHost = config?.hostName else {
            return true
        }

        // If a hostname is configured, only connect if it matches or contains the required host
        guard let endpointHost = NetServiceTransport.hostname(from: endpoint) else {
            print("[Atlantis] ⚠️ Could not determine hostname for endpoint \(endpoint.debugDescription). Allowing connection attempt.")
            return true // Allow connection if hostname cannot be determined
        }

        // compare
        var lowercasedRequiredHost = requiredHost.lowercased()
        let lowercasedEndpointHost = endpointHost.lowercased()

        // Remove trailing dot from required host if present
        if lowercasedRequiredHost.hasSuffix(".") {
            lowercasedRequiredHost = String(lowercasedRequiredHost.dropLast())
        }

        // Allow connection if the endpoint host *contains* the required host (case-insensitive)
        // This handles cases like required="mac-mini.local" and endpoint="Proxyman-mac-mini.local"
        // or "Proxyman-mac-mini.local" and "mac-mini.local"
        // This is useful for local network discovery where the hostname might vary slightly because Proxyman macOS is stil using old-fashioned BonjourService class.
        // Meanwhile, Atlantis now uses NWBrowser for discovery
        if !lowercasedEndpointHost.contains(lowercasedRequiredHost) {
            print("[Atlantis] ⏭️ Skipping connection to \(endpointHost) (Required host \(requiredHost) not found within endpoint host)")
            return false
        }

        return true
    }

    // Helper to extract hostname string from NWEndpoint
    private class func hostname(from endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .hostPort(let host, _):
            return "\(host)"
        case .service(let name, _, _, _):
            // Extract hostname from service name (e.g., "MyMac._Proxyman._tcp.local.")
            // This might need refinement based on actual service name formats
            return name
        default:
            return nil
        }
    }

    // Internal stop method to be called on the queue
    private func stopInternal() {
        browser?.cancel()
        browser = nil
        // Cancel all active connections before removing them
        connections.forEach { $0.cancel() }
        connections.removeAll()
        pendingFrames.removeAll()
        pendingFrameBytes = 0
        pendingDropMarker = nil
        isSendingFrame = false
        sendGeneration &+= 1
        simulatorRetryCount = 0 // Reset retry count on stop
        print("[Atlantis] Transport stopped and connections cleared.") // Added log for clarity
    }
}

// MARK: - Notifications

extension NetServiceTransport {

    private func initNotification() {
        #if os(iOS)
        // Memory Warning notification is only available on iOS
        NotificationCenter.default.addObserver(self, selector: #selector(self.didReceiveMemoryNotification), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    @objc private func didReceiveMemoryNotification() {
        queue.async {[weak self] in
            print("[Atlantis] Received memory warning. Clearing pending packages.")
            self?.pendingFrames.removeAll()
            self?.pendingFrameBytes = 0
            self?.pendingDropMarker = nil
        }
    }

    private func getEndpointForLocalhost() -> NWEndpoint {
        let port = Constants.directConnectionPort
        let host = NWEndpoint.Host("localhost") // Simulators connect to localhost
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        return endpoint
    }
}

#if DEBUG
// Helper for logging endpoint descriptions
extension NWEndpoint {
    var debugDescription: String {
        switch self {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        case .service(let name, let type, let domain, _):
            return "\(name).\(type).\(domain)"
        case .unix(let path):
            return "unix:\(path)"
        case .url(let url):
            return url.absoluteString
        case .opaque:
            return "opaque"
        @unknown default:
            return "UnknownEndpoint"
        }
    }
}
#endif
