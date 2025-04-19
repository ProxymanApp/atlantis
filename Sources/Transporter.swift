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
}

extension Serializable {

    func toCompressedData() -> Data? {
        guard let rawData = self.toData() else { return nil }

        // Compress data by gzip
        // Fallback to raw data if it's unsuccess
        return rawData.gzip() ?? rawData
    }
}

final class NetServiceTransport: NSObject {

    struct Constants {
        static let netServiceType = "_Proxyman._tcp"
        static let netServiceDomain = ""
    }

    // MARK: - Variables

    // For some reason, Stream Task could send a big file
    // https://github.com/ProxymanApp/atlantis/issues/57
    static let MaximumSizePackage = 52428800 // 50Mb

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.netservices") // Serial queue for thread safety
    private var pendingPackages: [Serializable] = []
    private var config: Configuration?

    // Multiple task connection support using NWConnection
    private var connections: [NWConnection] = []

    // The maximum number of pending item to prevent Atlantis consumes too much RAM
    private let maxPendingItem = 50

    // MARK: - Init

    override init() {
        super.init()
        initNotification()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stop() // Ensure browser and connections are cleaned up
    }
}

// MARK: - Transporter

extension NetServiceTransport: Transporter {

    func start(_ config: Configuration) {
        self.config = config

        queue.async {
            // Reset all current connections and browser if needed
            self.stopInternal()

            // Always use NWBrowser for discovery now
            print("[Atlantis] Looking for Proxyman app using Bonjour (\(Constants.netServiceType))...")
            self.startBrowsing()
        }
    }

    func stop() {
        queue.async {
            self.stopInternal()
        }
    }

    func send(package: Serializable) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            // Ensure we have at least one ready connection
            guard strongSelf.connections.contains(where: { $0.state == .ready }) else {
                // If no connection is ready, append to pending list
                strongSelf.appendToPendingList(package)
                return
            }

            // Send to all ready connections
            strongSelf.streamToAllReadyConnections(package: package)
        }
    }

    private func streamToAllReadyConnections(package: Serializable) {
        // Compress data by gzip
        guard let compressedData = package.toCompressedData() else { return }

        // Send to all *ready* connections
        for connection in connections where connection.state == .ready {
            send(connection: connection, data: compressedData)
        }
    }

    private func send(connection: NWConnection, data: Data) {
        guard connection.state == .ready else {
            print("[\(connection.endpoint.debugDescription)] ⚠️ Attempted to send data on a non-ready connection. State: \(connection.state)")
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
        }))
    }

    private func appendToPendingList(_ package: Serializable) {
        // Remove oldest items if limit exceeded (FIFO approach)
        while pendingPackages.count >= maxPendingItem {
            pendingPackages.removeFirst()
        }
        pendingPackages.append(package)
    }

    private func flushAllPendingPackagesIfNeed() {
        guard !pendingPackages.isEmpty else { return }
        print("[Atlantis] Flushing \(pendingPackages.count) pending items...")
        let packagesToFlush = pendingPackages // Copy packages
        pendingPackages.removeAll() // Clear immediately
        for package in packagesToFlush {
            streamToAllReadyConnections(package: package) // Stream copies
        }
        print("[Atlantis] Finished flushing pending items.")
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
            print("[Atlantis] Browser state updated: \(newState)")
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
                @unknown default:
                    fatalError()
                }
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
                print("[\(endpointDesc)] Connection state: Setup")
            case .preparing:
                print("[\(endpointDesc)] Connection state: Preparing")
            case .ready:
                print("[\(endpointDesc)] ✅ Connection established.")
                // Send initial connection info and flush pending
                strongSelf.sendConnectionPackage(connection: connection)
                strongSelf.flushAllPendingPackagesIfNeed()
            case .waiting(let error):
                print("[\(endpointDesc)] ⚠️ Connection waiting: \(error).")
            case .failed(let error):
                print("[\(endpointDesc)] ❌ Connection failed: \(error).")
                // Remove the failed connection
                strongSelf.connections.removeAll { $0 === connection }
            case .cancelled:
                print("[\(endpointDesc)] 🛑 Connection cancelled.")
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
        print("[\(connection.endpoint.debugDescription)] Sending connection package...")
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
        case .service(let name, let type, let domain, _):
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
        connections.removeAll()
        pendingPackages.removeAll()
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
            self?.pendingPackages.removeAll()
        }
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
        @unknown default:
            return "UnknownEndpoint"
        }
    }
}
#endif
