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
    }

    // MARK: - Variables

    private let id: String
    private let messageType: MessageType
    private let content: Data?
    private let buildVersion: String?

    // MARK: - Init

    private init(id: String, messageType: Message.MessageType, content: Data?) {
        self.id = id
        self.messageType = messageType
        self.content = content
        self.buildVersion = Atlantis.buildVersion
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
}

// MARK: - Serializable

extension Message: Serializable {

    func toData() -> Data? {
        do {
            return try JSONEncoder().encode(self)
        } catch let error {
            print(error)
        }
        return nil
    }
}
