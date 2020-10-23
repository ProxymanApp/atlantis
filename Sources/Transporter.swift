//
//  Transporter.swift
//  atlantis-iOS
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

public protocol Transporter {

    func start()
    func send(package: Package)
}

final class NetServiceTransport: NSObject {

    // MARK: - Variabls

    private let serviceBrowser: NetServiceBrowser
    private let configuration: Configuration
    private var services: [NetService] = []
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.netservices")

    // MARK: - Public

    init(configuration: Configuration) {
        self.configuration = configuration
        self.serviceBrowser = NetServiceBrowser()
        super.init()
        serviceBrowser.delegate = self
    }

    func start() {
        // Reset all current connections
        reset()

        // Start searching
        serviceBrowser.searchForServices(ofType: configuration.netServiceType, inDomain: configuration.netServiceDomain)
    }

    private func reset() {
        queue.sync {
            services.forEach { $0.stop() }
            services.removeAll()
            serviceBrowser.stop()
        }
    }
}

// MARK: - Transporter

extension NetServiceTransport: Transporter {

    func send(package: Package) {
        print("Send package = \(package)")
    }
}

// MARK: - Private

extension NetServiceTransport {

    private func connectToService(_ service: NetService) {
        print("Connect to server address count = \(service.addresses?.count ?? 0)")
    }
}

// MARK: - NetServiceBrowserDelegate

extension NetServiceTransport: NetServiceBrowserDelegate {

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("didFind service \(service)")
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            strongSelf.services.append(service)
            service.delegate = strongSelf
            service.resolve(withTimeout: 30)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("didRemove service \(service)")
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            if let index = strongSelf.services.firstIndex(where: { $0 === service }) {
                strongSelf.services.remove(at: index)
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("[Atlantis][ERROR] didNotSearch \(errorDict)")
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print("netServiceBrowserWillSearch")
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("netServiceBrowserDidStopSearch")
    }
}

// MARK: - NetServiceDelegate

extension NetServiceTransport: NetServiceDelegate {

    func netServiceDidResolveAddress(_ sender: NetService) {
        print("netServiceDidResolveAddress")
        connectToService(sender)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("[Atlantis][ERROR] didNotPublish \(errorDict)")
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("[Atlantis][ERROR] didNotResolve \(errorDict)")
    }
}
