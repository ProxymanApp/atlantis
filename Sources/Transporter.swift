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

    // MARK: - Public

    init(configuration: Configuration) {
        self.configuration = configuration
        self.serviceBrowser = NetServiceBrowser()
        super.init()
        self.serviceBrowser.delegate = self
    }

    func start() {
        serviceBrowser.searchForServices(ofType: configuration.netServiceType, inDomain: configuration.netServiceType)
    }
}

// MARK: - Transporter

extension NetServiceTransport: Transporter {

    func send(package: Package) {

    }
}

// MARK: - NetServiceBrowserDelegate

extension NetServiceTransport: NetServiceBrowserDelegate {

}
