//
//  Transporter.swift
//  atlantis-iOS
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

protocol Transporter {

    func start(_ config: Configuration)
    func stop()
    func send(package: Serializable)
}

protocol Serializable {

    func toData() -> Data?
}

final class NetServiceTransport: NSObject {

    struct Constants {
        static let netServiceType = "_Proxyman._tcp"
        static let netServiceDomain = ""
    }

    // MARK: - Variabls

    private let serviceBrowser: NetServiceBrowser
    private var services: [NetService] = []
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.netservices") // Serial on purpose
    private let session: URLSession
    private var task: URLSessionStreamTask?
    private var pendingPackages: [Serializable] = []
    private var config: Configuration?

    // MARK: - Init

    override init() {
        self.serviceBrowser = NetServiceBrowser()
        let config = URLSessionConfiguration.default
        #if os(iOS)
        config.waitsForConnectivity = true
        #endif
        session = URLSession(configuration: config)
        super.init()
        serviceBrowser.delegate = self
    }
}

// MARK: - Transporter

extension NetServiceTransport: Transporter {

    func start(_ config: Configuration) {
        if let hostName = config.hostName {
            print("[Atlantis] Try Connecting to Proxyman with HostName = \(hostName)")
        } else {
            print("[Atlantis] Looking for Proxman app in the network...")
        }

        self.config = config
        start()
    }

    private func start() {
        // Reset all current connections if need
        stop()

        // Start searching
        // Have to run on MainThread, otherwise, the service will stop for some reason
        serviceBrowser.searchForServices(ofType: Constants.netServiceType, inDomain: Constants.netServiceDomain)
    }

    func stop() {
        queue.sync {
            services.forEach { $0.stop() }
            services.removeAll()
            serviceBrowser.stop()
        }
    }

    func send(package: Serializable) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            guard let task = strongSelf.task, task.state == .running else {
                // It means the connection is not ready
                // We add the package to the pending list
                strongSelf.appendToPendingList(package)
                return
            }

            // Send the main one
            strongSelf.stream(package: package)
        }
    }

    private func stream(package: Serializable) {
        guard let rawData = package.toData() else { return }

        // Compress data by gzip
        // Fallback to raw data if it's unsuccess
        let data = rawData.gzip() ?? rawData

        // Compose a message
        // [1]: the length of the second message. We reserver 8 bytes to store this data
        // [2]: The actual message

        let buffer = NSMutableData()
        var lengthPackage = data.count
        buffer.append(&lengthPackage, length: Int(MemoryLayout<UInt64>.stride))
        buffer.append([UInt8](data), length: data.count)

        // Write data
        task?.write(buffer as Data, timeout: 60) {[weak self] (error) in
            guard let strongSelf = self else { return }
            if let nsError = error as NSError? {
                // The socket is disconnected, we should add to the pending list
                if nsError.code == 57 {
                    // Should be called in the serial queue because it's called from URLSession's queue
                    strongSelf.queue.async {
                        strongSelf.appendToPendingList(package)
                    }
                } else {
                    print("[Atlantis][ERROR] Write socket Error: \(String(describing: error))")
                }
            }
        }
    }

    private func appendToPendingList(_ package: Serializable) {
        pendingPackages.append(package)
    }

    private func flushAllPendingIfNeed() {
        guard !pendingPackages.isEmpty else { return }
        print("[Atlantis] Flush \(pendingPackages.count) items")
        for package in pendingPackages {
            stream(package: package)
        }
        pendingPackages.removeAll()
    }
}

// MARK: - Private

extension NetServiceTransport {

    private func connectToService(_ service: NetService) {

        if let hostName = service.hostName {
            print("[Atlantis] Found Proxyman with HostName = \(hostName)")
        }

        // If user want to connect to particular host name
        // We should find exact Proxyman
        // by default, config.hostName is nil, it will connect all available Proxyman app
        if let hostName = config?.hostName,
           let serviceHostName = service.hostName {

            // Skip if it's not the service we're looking for
            if hostName.lowercased() != serviceHostName.lowercased() {
                print("[Atlantis] Skip connect to \(serviceHostName)")
                return
            }
        }

        // Stop previous connection if need
        if let task = task {
            task.closeWrite()
        }

        guard let hostName = service.hostName else {
            print("[Atlantis][ERROR] Could not receive the host name from NetService!")
            return
        }

        // use HostName and Port instead of streamTask(with service: NetService)
        // It's crashed on iOS 14 for some reasons
        print("[Atlantis] ✅ Connect to \(hostName)")
        task = session.streamTask(withHostName: hostName, port: service.port)

        // As we're going to call the -resume method, it will be swizzled by Atlantis
        // We should not do it
        // Set a runtime id that we can receive later
        task?.setFromAtlantisFramework()

        // Start the socket
        task?.resume()

        // All pending
        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            //
            if let config = strongSelf.config {
                // Create a first connection message
                // which contains the project, device metadata
                let connectionMessage = Message.buildConnectionMessage(id: config.id, item: ConnectionPackage(config: config))

                // Add to top of the pending list, when the connection is available, it will send firstly
                strongSelf.pendingPackages.insert(connectionMessage, at: 0)
            }

            self?.flushAllPendingIfNeed()
        }
    }
}

// MARK: - NetServiceBrowserDelegate

extension NetServiceTransport: NetServiceBrowserDelegate {

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            strongSelf.services.append(service)
            service.delegate = strongSelf
            service.resolve(withTimeout: 30)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }

            // For some reason, we the service in this method is not the same with the server when we append.
            // It's impossible to know which service is
            // Best case, we should remove all
            strongSelf.services.removeAll()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        // Retry again after going from the foregronud
        start()
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
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
