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

    enum CodingKeys: CodingKey {
        case id
        case messageType
        case content
        case buildVersion
    }

    // MARK: - Variables

    private let id: String
    private let messageType: MessageType
    private let content: Data?
    private let buildVersion: String?

    // Hold the real package, but not perform JSON Encoded
    // Useful for testing
    private(set) var package: Serializable?

    // MARK: - Init

    private init(id: String, messageType: Message.MessageType, content: Data?, package: Serializable) {
        self.id = id
        self.messageType = messageType
        self.content = content
        self.buildVersion = Atlantis.buildVersion

        /// only available if it's in DEBUG and TESTING Mode
        /// Hold the real Request/Response package, so we can test whether or not the Request/Response are captured properly
        if Enviroment.isTestingEnv() {
            self.package = package
        }
    }

    // MARK: - Helper Builder

    static func buildConnectionMessage(id: String, item: Serializable) -> Message {
        return Message(id: id, messageType: MessageType.connection, content: item.toData(), package: item)
    }

    static func buildTrafficMessage(id: String, item: Serializable) -> Message {
        return Message(id: id, messageType: MessageType.traffic, content: item.toData(), package: item)
    }

    static func buildWebSocketMessage(id: String, item: Serializable) -> Message {
        return Message(id: id, messageType: MessageType.websocket, content: item.toData(), package: item)
    }
    
    init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<Message.CodingKeys> = try decoder.container(keyedBy: Message.CodingKeys.self)
        
        self.id = try container.decode(String.self, forKey: Message.CodingKeys.id)
        self.messageType = try container.decode(Message.MessageType.self, forKey: Message.CodingKeys.messageType)
        self.content = try container.decodeIfPresent(Data.self, forKey: Message.CodingKeys.content)
        self.buildVersion = try container.decodeIfPresent(String.self, forKey: Message.CodingKeys.buildVersion)
    }
    
    func encode(to encoder: any Encoder) throws {
        var container: KeyedEncodingContainer<Message.CodingKeys> = encoder.container(keyedBy: Message.CodingKeys.self)
        
        try container.encode(self.id, forKey: Message.CodingKeys.id)
        try container.encode(self.messageType, forKey: Message.CodingKeys.messageType)
        try container.encodeIfPresent(self.content, forKey: Message.CodingKeys.content)
        try container.encodeIfPresent(self.buildVersion, forKey: Message.CodingKeys.buildVersion)
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
