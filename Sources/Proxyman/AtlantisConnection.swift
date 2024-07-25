//
//  AtlantisConnection.swift
//  ProxymanCore
//
//  Created by Nghia Tran on 10/26/20.
//  Copyright © 2020 com.nsproxy.proxy. All rights reserved.
//

import Foundation
import Network

protocol AtlantisConnectionDelegate: AnyObject {

    func atlantisConnectionDidStop(id: String)
    func atlantisConnectionDidReceive(message: AtlantisModels.Message)
}

final class AtlantisConnection {

    enum ConnectionError: Error, LocalizedError {
        case invalidLengthMessage

        var errorDescription: String? {
            switch self {
            case .invalidLengthMessage:
                return "Invalid Length Message"
            }
        }
    }

    // MARK: - Variables

    weak var delegate: AtlantisConnectionDelegate?
    let id: String
    private let connection: NWConnection

    // MARK: - Init

    init(nwConnection: NWConnection) {
        connection = nwConnection
        id = UUID().uuidString
    }

    // MARK: - Public

    func start(queue: DispatchQueue) {
        connection.stateUpdateHandler = {[weak self] state in
            guard let strongSelf = self else { return }
            switch state {
            case .waiting(let error):
                strongSelf.connectionDidFail(error: error)
            case .ready:
                print("connection \(strongSelf.id) ready")

                // Must call after the connection is ready
                // Otherwise, we can get the error: Connection reset by peer
                // https://github.com/ProxymanApp/Proxyman/issues/1439
                strongSelf.receiveFirstMessage()
            case .failed(let error):
                strongSelf.connectionDidFail(error: error)
            case .setup:
                break
            case .preparing:
                break
            case .cancelled:
                strongSelf.connectionDidEnd()
            @unknown default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func stop(error: Error? = nil) {
        print("Connection id=\(id) is stopped. Error=\(String(describing: error))")
        if connection.state != .cancelled {
            connection.cancel()
            delegate?.atlantisConnectionDidStop(id: id)
        }
    }
}

// MARK: - Private

extension AtlantisConnection {

    private func connectionDidFail(error: Error) {
        stop(error: error)
    }

    private func connectionDidEnd() {
        stop(error: nil)
    }

    // Inspire from https://github.com/fpillet/NetworkingWorkshopSwiftNIO/blob/master/iOS-completed/ChatClient/Model/ChatClientService.swift
    private func receiveFirstMessage() {
        let byLength = Int(MemoryLayout<UInt64>.stride)
        connection.receive(minimumIncompleteLength: byLength, maximumLength: byLength) {[weak self] (data, _, _, error) in
            guard let strongSelf = self else { return }
            strongSelf._handleFirstMessage(error, data)
        }
    }

    private func receiveSecondMessage(byLength: Int) {
        guard connection.state == .ready else {
            stop(error: nil)
            return
        }
        connection.receive(minimumIncompleteLength: byLength, maximumLength: byLength) {[weak self] (data, _, _, error) in
            guard let strongSelf = self else { return }
            strongSelf._handleSecondMessage(error, data)
        }
    }

    private func _handleFirstMessage(_ error: NWError?, _ data: Data?) {
        if let error = error {
            connectionDidFail(error: error)
            return
        }

        if let data = data, !data.isEmpty {

            // Fix: Ensure that the data length exactly matches MemoryLayout<UInt64>.stride before attempting to copy bytes.
            guard data.count >= MemoryLayout<UInt64>.stride else {
                print("❌Invalid data size received. Expected size: \(MemoryLayout<UInt64>.stride), received: \(data.count)")
                connectionDidFail(error: ConnectionError.invalidLengthMessage)
                return
            }

            // Cast byte to Int64
            var length: UInt64 = 0
            _ = withUnsafeMutablePointer(to: &length) { (length) -> Int in
                data.copyBytes(to: UnsafeMutableBufferPointer(start: length, count: MemoryLayout<UInt64>.stride))
            }

            if length > 0 && length < UInt64.max {
                print("connection \(id) did receive FIRST message: Length = \(length)")
                receiveSecondMessage(byLength: Int(length))
            } else {
                print("❌receiveFirstMessage with valid length \(length)")
                connectionDidFail(error: ConnectionError.invalidLengthMessage)
            }
        } else {
            // in the improbable case where data is nil, we still want to
            // keep reading from the connection
            receiveFirstMessage()
        }
    }

    private func _handleSecondMessage(_ error: NWError?, _ data: Data?) {
        if let error = error {
            print("❌Network error received: \(error)")
            connectionDidFail(error: error)
            return
        }

        guard let data = data else {
            receiveFirstMessage()
            return
        }

        do {
            // Attempt decompressing the gzip data
            let rawData = data.gunzip() ?? data
            let message = try JSONDecoder().decode(AtlantisModels.Message.self, from: rawData)
            delegate?.atlantisConnectionDidReceive(message: message)

            // Only receive the next message if the current one is completed!
            receiveFirstMessage()

        } catch let error {
            // if there are any errors, just stop it, don't call the nextFirstMessage, the app will be crashed!
            print(error)
            connectionDidFail(error: error)
        }
    }

}
