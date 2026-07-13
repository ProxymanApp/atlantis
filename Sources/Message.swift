//
//  Message.swift
//  atlantis
//
//  Created by Nghia Tran on 10/25/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

struct Message: Codable {

    enum MessageType: String, Codable {
        case connection // First message, contains: Project, Device metadata
        case traffic // Request/Response log
        case websocket // for websocket send/receive/close
        case grpc // gRPC-Swift client lifecycle and serialized messages
    }

    // MARK: - Variables

    private let id: String
    private let messageType: MessageType
    private let content: Data?
    private let buildVersion: String?
    private var transportPriority: TransportRetentionPriority = .essential
    private var droppedPayloadContent: Data? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case messageType
        case content
        case buildVersion
    }

    // MARK: - Init

    private init(id: String,
                 messageType: Message.MessageType,
                 content: Data?,
                 transportPriority: TransportRetentionPriority = .essential,
                 droppedPayloadContent: Data? = nil) {
        self.id = id
        self.messageType = messageType
        self.content = content
        self.buildVersion = Atlantis.buildVersion
        self.transportPriority = transportPriority
        self.droppedPayloadContent = droppedPayloadContent
    }

    // MARK: - Helper Builder

    static func buildConnectionMessage(id: String, item: Serializable) -> Message {
        return Message(id: id, messageType: MessageType.connection, content: item.toData())
    }

    static func buildTrafficMessage(id: String, item: Serializable) -> Message {
        return Message(id: id, messageType: MessageType.traffic, content: item.toData())
    }

    static func buildWebSocketMessage(id: String, item: Serializable) -> Message {
        return Message(id: id, messageType: MessageType.websocket, content: item.toData())
    }

    static func buildGRPCMessage(id: String, item: GRPCEventPackage) -> Message {
        let droppedPayloadContent = item.containsPayload
            ? item.omittingPayloadBecauseBufferIsFull().toData()
            : nil
        return Message(id: id,
                       messageType: .grpc,
                       content: item.toData(),
                       transportPriority: item.containsPayload ? .payload : .essential,
                       droppedPayloadContent: droppedPayloadContent)
    }
}

// MARK: - Serializable

extension Message: Serializable {

    var retentionPriority: TransportRetentionPriority {
        return transportPriority
    }

    var replacementWhenDropped: Serializable? {
        guard let droppedPayloadContent = droppedPayloadContent else { return nil }
        return Message(id: id,
                       messageType: messageType,
                       content: droppedPayloadContent)
    }

    func toData() -> Data? {
        do {
            return try JSONEncoder().encode(self)
        } catch let error {
            print(error)
        }
        return nil
    }
}
