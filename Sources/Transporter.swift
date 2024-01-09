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

private extension NWBrowser.Result {
    var name: String? {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        default:
            return nil
        }
    }
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

    // MARK: - Variabls

    // For some reason, Stream Task could send a big file
    // https://github.com/ProxymanApp/atlantis/issues/57
    static let MaximumSizePackage = 52428800 // 50Mb

    private var browser: NWBrowser!
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.netservices") // Serial on purpose
    private let session: URLSession
    private var pendingPackages: [Serializable] = []
    private var config: Configuration?

    // Multiple task connection
    // it allows Atlantis can simultaneously connect to many Proxyman instances
    // https://github.com/ProxymanApp/atlantis/issues/72

    @Protected
    private var connections: [NWConnection]

    // The maximum number of pending item to prevent Atlantis consumes too much RAM
    // https://github.com/ProxymanApp/atlantis/issues/74
    private let maxPendingItem = 30

    public private(set) var servers: Set<NWBrowser.Result> = [] {
        didSet {
            print("Set servers: \(servers.map { $0.name ?? "" })")
        }
    }
    public private(set) var browserState: NWBrowser.State = .setup {
        didSet { print("Set browser state \(browserState)") }
    }
    public private(set) var browserError: NWError?

    // MARK: - Init

    override init() {
        self.connections = []
        let config = URLSessionConfiguration.default
        #if os(iOS)
        config.waitsForConnectivity = true
        #endif
        session = URLSession(configuration: config)
        super.init()
        initNotification()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Transporter

extension NetServiceTransport: Transporter {

    func start(_ config: Configuration) {
        if let hostName = config.hostName {
            print("[Atlantis] Try Connecting to Proxyman with HostName = \(hostName)")
        } else {
            print("[Atlantis] Looking for Proxyman app in the network...")
        }

        self.config = config
        start()
    }

    private func start() {
        // Reset all current connections if need
        stop()

        // Must init new Browser
        // if we cancel it, it cannot be started again! You must create a new browser object and start it.
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Constants.netServiceType, domain: Constants.netServiceDomain), using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] in
            self?.browserDidUpdateState($0)
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.browserDidUpdateResults(results)
        }
        browser.start(queue: .main)
    }

    func stop() {
        servers.removeAll()
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    func send(package: Serializable) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            // Make sure we have 1 ready connection
            guard !strongSelf.connections.isEmpty,
                  strongSelf.connections.contains(where: { $0.state == .ready })  else {
                // If the connection is not ready
                // We add the package to the pending list
                strongSelf.appendToPendingList(package)
                return
            }

            // Send to all connections
            strongSelf.streamToAllConnections(package: package)
        }
    }

    private func streamToAllConnections(package: Serializable) {
        // Compress data by gzip
        guard let compressedData = package.toCompressedData() else { return }

        // Send to all available connection
        for connection in connections {
            send(connection: connection, data: compressedData)
        }
    }

    private func send(connection: NWConnection, data: Data) {
        guard connection.state == .ready else {
            print("⚠️ The connection is not ready. It might be a bug!")
            return
        }

        // Compose a message
        // [1]: the length of the second message. We reserver 8 bytes to store this data
        // [2]: The actual message

        // 1. Send length of the message first
        let headerData = NSMutableData()
        var lengthPackage = data.count
        headerData.append(&lengthPackage, length: Int(MemoryLayout<UInt64>.stride))

        // Send the message, must use isComplete = false
        connection.send(content: headerData, isComplete: false, completion: .contentProcessed({ error in
            if let error = error {
                print("[Atlantis][Error] Error sending frame header: \(error)")
            }
        }))

        // 2. send the actual message
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("[Atlantis][Error] Error sending frame content: \(error)")
            }
        }))
    }

    private func appendToPendingList(_ package: Serializable) {
        // For the sake of simplicity, we remove all items if it exceeds the limit
        // In the future, we can implement a deque
        if pendingPackages.count >= maxPendingItem {
            pendingPackages.removeAll()
        }
        pendingPackages.append(package)
    }

    private func flushAllPendingPackagesIfNeed() {
        guard !pendingPackages.isEmpty else { return }
        print("[Atlantis] Flush \(pendingPackages.count) items")
        for package in pendingPackages {
            streamToAllConnections(package: package)
        }
        pendingPackages.removeAll()
    }
}

// MARK: - Private

extension NetServiceTransport {

    private func connectToService(_ service: NetService) {

        if let hostName = service.hostName {
            print("[Atlantis] 🔎 Found Proxyman at HostName = \(hostName)")
        }

        // If user want to connect to particular host name
        // We should find exact Proxyman
        // by default, config.hostName is nil, it will connect all available Proxyman app
        if let hostName = config?.hostName,
           let serviceHostName = service.hostName {

            // Skip if it's not the service we're looking for
            if hostName.lowercased() != serviceHostName.lowercased() {
                print("[Atlantis] ⏭️ Avoid connecting to \(serviceHostName)")
                return
            }
        }

        guard let hostName = service.hostName else {
            print("[Atlantis][ERROR] Could not receive the host name from NetService!")
            return
        }

        // safe thread
        queue.async {[weak self] in
            guard let strongSelf = self else {
                return
            }

            // Don't allow to connect multiple times to the same Host
            let isDuplicated = strongSelf.connections.contains { connection in
                switch connection.endpoint {
                case .service(let name, _, _, _):
                    return name == service.name
                default:
                    break
                }
                return false
            }
            if isDuplicated {
                print("[Atlantis] ⚠️ Avoid connecting to \(hostName) because it's already connected!")
                return
            }

            // use HostName and Port instead of streamTask(with service: NetService)
            // It's crashed on iOS 14 for some reasons
            print("[Atlantis] ✅ Connect to \(hostName)")

            // Use NWConnection instead of URLSessionStreamTask
            // Because we've recently encountered some crashed when reading/writing data from Proxyman app
            // The problem might be we use different two connection classes
            // Proxyman uses NWConnection, but the old version of Atlantis used URLSessionStreamTask
            //
            // Use the same NWConnection in both apps might fix the crash. However, NWConnection requires macOS 10.14 and iOS 13.0
            //
            let connection = NWConnection(to: .service(name: service.name, type: service.type, domain: service.domain, interface: nil), using: .tcp)
            strongSelf.setupConnectionStateHandler(connection)
            strongSelf.connections.append(connection)

            // Start
            connection.start(queue: strongSelf.queue)
        }
    }

    private func setupConnectionStateHandler(_ connection: NWConnection) {
        connection.stateUpdateHandler = {[weak self] (newState) in
            guard let strongSelf = self else { return }
            switch (newState) {
            case .setup,
                    .preparing:
                break
            case .ready:
                print("[Atlantis] Connection established")

                // After the connection is established, Tell Proxyman app that who we are
                strongSelf.queue.async {
                    strongSelf.sendConnectionPackage(connection: connection)
                }

            case .waiting(let error):
                print("[Atlantis] Connection to server waiting to establish, error=\(error)")
            case .failed(let error):
                print("[Atlantis] ❌ Connection to Proxyman app is failed, error=\(error)")
                strongSelf.queue.async {
                    strongSelf.connections.removeAll { $0 === connection }
                }
            case .cancelled:
                print("[Atlantis] Connection to Proxyman app is cancelled!")
                strongSelf.queue.async {
                    strongSelf.connections.removeAll { $0 === connection }
                }
            @unknown default:
                break
            }
        }
    }

    private func sendConnectionPackage(connection: NWConnection) {
        guard let config = config else {
            return
        }

        // Create a first connection message
        // which contains the project, device metadata
        let connectionMessage = Message.buildConnectionMessage(id: config.id, item: ConnectionPackage(config: config))
        guard let data = connectionMessage.toCompressedData() else {
            return
        }
        send(connection: connection, data: data)

        // Flush all waiting data
        flushAllPendingPackagesIfNeed()
    }
}

// MARK: - NetServiceDelegate

extension NetServiceTransport: NetServiceDelegate {

    func netServiceDidResolveAddress(_ sender: NetService) {
        connectToService(sender)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("[Atlantis][ERROR] didNotPublish \(errorDict)")
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("[Atlantis][ERROR] didNotResolve \(errorDict)")
    }
}

// MARK: - Private

extension NetServiceTransport {

    private func initNotification() {
        #if os(iOS)
        // Memory Warning notification is only available on iOS
        NotificationCenter.default.addObserver(self, selector: #selector(self.didReceiveMemoryNotification), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #endif
    }

    @objc private func didReceiveMemoryNotification() {
        queue.async {[weak self] in
            self?.pendingPackages.removeAll()
        }
    }
}

extension NetServiceTransport {

    private func browserDidUpdateState(_ newState: NWBrowser.State) {
        print("Browser did update state to \(newState)")

        browserState = newState
        browserError = nil

        switch newState {
        case .waiting(let error):
            print("[Atlantis] ❌ Browser waiting with error: \(error.debugDescription)")
            browserError = error
        case .failed(let error):
            print("[Atlantis] ❌ Browser failed with error: \(error.debugDescription)")
            browserError = error
//            scheduleBrowserRetry()
        case .ready:
            servers = browser.browseResults
        case .cancelled:
            servers = []
        default:
            break
        }
    }

    private func browserDidUpdateResults(_ results: Set<NWBrowser.Result>) {
        print("browserDidUpdateResults")
        servers = results
        connectAutomaticallyIfNeeded()
    }

    private func connectAutomaticallyIfNeeded() {

    }
}
