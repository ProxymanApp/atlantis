//
//  AtlantisService.swift
//  ProxymanCore
//
//  Created by Nghia Tran on 10/26/20.
//  Copyright © 2020 com.nsproxy.proxy. All rights reserved.
//

import Foundation
import Network

public protocol AtlantisServiceDelegate: AnyObject {

    func atlantisServiceDidUse()
    func atlantisServiceHasNewMessage(_ message: AtlantisModels.Message)
}

extension Notification.Name {
    static let IsAtlantisServiceEnabledDidChangeNotification = Notification.Name("IsAtlantisServiceEnabledDidChangeNotification")
    static let UnsupportAtlantisVersionNotification = Notification.Name("UnsupportAtlantisVersionNotification")
}

public final class AtlantisService: NSObject {

    public static let shared = AtlantisService()
    private static let minimumSupportVersion = "1.4.2"

    private struct Constants {

        static let netServiceDomain = ""
        static let netServiceType = "_Proxyman._tcp"
        static let netServiceName = "Proxyman"
        static let netServicePort: Int32 = 10909

    }

    // MARK: - Variables

    public weak var delegate: AtlantisServiceDelegate?
    private var isConnected = false
    private var connections: [String: AtlantisConnection]? = [:]
    private let queue = DispatchQueue(label: "com.proxyman.atlantis")
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

    public static let hostName = ProcessInfo.processInfo.hostName

    // MARK: - Init

    override init() {
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

    public func startIfNeed() throws {
        try start()
    }

    private func start() throws {
        // Must have a guard to prevent Beach Ball at launch
        // https://github.com/ProxymanApp/Proxyman/issues/721
        guard !isConnected else { return }
        guard listener == nil else { return }
        isConnected = true

        // Configure listener for Bonjour Advertising
        // Must publish with unique name
        // Otherwise, it will get collision errors if there are multiple Proxyman on the same network
        let uniqueServiceName = "\(Constants.netServiceName)-\(AtlantisService.hostName)"

        // Start the listener with service registration AND explicit port
        let parameters = NWParameters.tcp
        // Allow local network communication, crucial for Bonjour and direct connections.
        // This replaces the need for specific entitlements in many cases.
        parameters.includePeerToPeer = true 
        
        let port = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(Constants.netServicePort))
        listener = try NWListener(using: parameters, on: port) // Explicitly set the port
        listener.service = NWListener.Service(name: uniqueServiceName, type: Constants.netServiceType, domain: Constants.netServiceDomain)
        listener.stateUpdateHandler = self.stateDidChange(to:)
        listener.newConnectionHandler = self.didAccept(nwConnection:)
        listener.start(queue: queue)

        print("Atlantis Bonjour Service advertising started with name: \(uniqueServiceName)")
    }

    public func stop() {
        guard let listener = listener else { return }
        guard isConnected else { return }

        isConnected = false

        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        print("Atlantis Bonjour Service stopped!")

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

// MARK: - NWListener Handlers (Moved from NetServiceDelegate extension)

extension AtlantisService {

    private func stateDidChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
            messageError = nil
            // Log the actual port the listener is using, which should be the one we requested (10909)
            print("Atlantis Server is ready at port \(listener.port?.debugDescription ?? "N/A")!!!") 
        case .failed(let error):
            messageError = error.localizedDescription
            print("Server failure, error: \(error.localizedDescription)")
            listener?.cancel()
            listener = nil
            isConnected = false
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
}

// MARK: - AtlantisConnectionDelegate

extension AtlantisService: AtlantisConnectionDelegate {

    func atlantisConnectionDidStop(id: String, error: Error?) {
        // Don't need to call in the queue.async
        // We close all connections from this queue, so this func will be executed on this queue too
        connections?.removeValue(forKey: id)
        if let error = error {
            print("server did close connection \(id) due to error: \(error.localizedDescription), count = \(connections?.count ?? 0)")
        } else {
            print("server did close connection \(id), count = \(connections?.count ?? 0)")
        }
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
        isSupportedCurrentAlanticVersion = !(version.compare(AtlantisService.minimumSupportVersion, options: .numeric) == .orderedAscending)
        NotificationCenter.default.post(name: .UnsupportAtlantisVersionNotification, object: isSupportedCurrentAlanticVersion)
    }
}
