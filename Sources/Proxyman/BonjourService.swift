//
//  BonjourService.swift
//  ProxymanCore
//
//  Created by Nghia Tran on 10/26/20.
//  Copyright © 2020 com.nsproxy.proxy. All rights reserved.
//

import Foundation
import Network

public protocol BonjourServiceDelegate: AnyObject {

    func atlantisServiceDidUse()
    func atlantisServiceHasNewMessage(_ message: AtlantisModels.Message)
}

public extension Notification.Name {
    static let IsAtlantisServiceEnabledDidChangeNotification = Notification.Name("IsAtlantisServiceEnabledDidChangeNotification")
    static let UnsupportAtlantisVersionNotification = Notification.Name("UnsupportAtlantisVersionNotification")
}

public final class BonjourService: NSObject {

    public static let shared = BonjourService()
    private static let minimumSupportVersion = "1.4.2"

    private struct Constants {

        static let netServiceDomain = ""
        static let netServiceType = "_Proxyman._tcp"
        static let netServiceName = "Proxyman"
        static let netServicePort: Int32 = 10909

    }

    // MARK: - Variables

    public weak var delegate: BonjourServiceDelegate?
    private var isConnected = false
    private var connections: [String: AtlantisConnection]? = [:]
    private let queue = DispatchQueue(label: "com.proxyman.atlantis")
    private var netService: NetService?
    private var listener: NWListener!
    private var connectionMetadata: [String: AtlantisModels.ConnectionPackage] = [:]
    private var shouldTrackAtlantisUsage = true
    public private(set) var isSupportedCurrentAlanticVersion = true
    public var errorMessageOnChanged: ((String?) -> Void)? = nil
    private(set) var messageError: String? {
        didSet {
            errorMessageOnChanged?(messageError)
        }
    }

    // MARK: - Init

    override init() {
        self.netService = nil
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.isAtlantisServiceIsChangedNoti(_:)),
                                               name: .IsAtlantisServiceEnabledDidChangeNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    public func start() throws {
        // Must have a guard to prevent Beach Ball at launch
        // https://github.com/ProxymanApp/Proxyman/issues/721
        guard !isConnected else { return }
        guard netService == nil else { return }
        isConnected = true

        // Start the listener
        listener = try NWListener(using: NWParameters.tcp, on: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(Constants.netServicePort)))
        listener.stateUpdateHandler = self.stateDidChange(to:)
        listener.newConnectionHandler = self.didAccept(nwConnection:)
        listener.start(queue: queue)

        // Start pushing Bonjour
        // Must publish with unique name
        // Otherwise, it will get NSNetServicesCollisionError if there are multiple Proxyman on the same network
        print("Bonjour Service is started!")
        let hostName = getCurrentHostName()
        let uniqueServiceName = "\(Constants.netServiceName)-\(hostName)"
        let service = NetService(domain: Constants.netServiceDomain, type: Constants.netServiceType, name: uniqueServiceName, port: Constants.netServicePort)
        service.delegate = self
        service.publish()
        self.netService = service
    }

    public func stop() {
        guard let listener = listener else { return }
        guard isConnected else { return }
        guard let netService = netService else {
            return
        }

        isConnected = false

        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        netService.stop()
        self.netService = nil
        print("Bonjour Service is stopped!")

        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let values = strongSelf.connections?.values
            if let connectionsValues = values {
                for connection in connectionsValues {
                    connection.stop()
                }
            }
        }
    }

    func getConnectionMetadata(id: String) -> AtlantisModels.ConnectionPackage? {
        return queue.sync {
            return connectionMetadata[id]
        }
    }

    @objc private func isAtlantisServiceIsChangedNoti(_ noti: Notification) {
        guard let value = noti.object as? Bool else {
            return
        }
        if value {
            try? start()
        } else {
            stop()
        }
    }
}

// MARK: - NetServiceDelegate

extension BonjourService: NetServiceDelegate {

    private func getCurrentHostName() -> String {
        #if os(macOS)
        return Host.current().name ?? UUID().uuidString
        #else
        return UUID().uuidString
        #endif
    }

    private func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
            messageError = nil
            print("Atlantis Server is ready at port \(Constants.netServicePort)!!!")
        case .failed(let error):
            messageError = error.localizedDescription
            print("❌ Server failure, error: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func didAccept(nwConnection: NWConnection) {
        queue.async {[weak self] in
            guard let strongSelf = self else { return }
            let connection = AtlantisConnection(nwConnection: nwConnection)
            connection.delegate = self
            strongSelf.connections?[connection.id] = connection
            connection.start(queue: strongSelf.queue)
            print("server did open connection \(connection.id)")
        }
    }

    public func netServiceDidPublish(_ sender: NetService) {
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        messageError = "\(errorDict)"
        print(errorDict)
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        messageError = "\(errorDict)"
        print(errorDict)
    }
}

// MARK: - AtlantisConnectionDelegate

extension BonjourService: AtlantisConnectionDelegate {

    func atlantisConnectionDidStop(id: String) {
        // Don't need to call in the queue.async
        // We close all connections from this queue, so this func will be executed on this queue too
        connections?.removeValue(forKey: id)
        print("server did close connection \(id), count = \(connections?.count ?? 0)")
    }

    func atlantisConnectionDidReceive(message: AtlantisModels.Message) {
        // Store the conneciton metadata if need
        // To receive the project and device information
        switch message.messageType {
        case .connection(let package):

            // Don't need queue.sync {}, since this func is called from this queue
            connectionMetadata[message.id] = package

            // When the connection is established, check compatible
            checkVersionCompatible(version: message.buildVersion)
        default:
            break
        }

        // Must run on main thread because from this method, we often deal with the UI
        DispatchQueue.main.async {[weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.atlantisServiceHasNewMessage(message)

            // For tracking
            if strongSelf.shouldTrackAtlantisUsage {
                strongSelf.shouldTrackAtlantisUsage = false
                strongSelf.delegate?.atlantisServiceDidUse()
            }
        }
    }

    private func checkVersionCompatible(version: String?) {
        guard let version = version else { return }

        // version < minimumVersion
        let isSupported = !(version.compare(BonjourService.minimumSupportVersion, options: .numeric) == .orderedAscending)
        isSupportedCurrentAlanticVersion = isSupported
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .UnsupportAtlantisVersionNotification, object: isSupported)
        }
    }
}
