//
//  GRPCEventPackage.swift
//  Atlantis
//
//  Created by Proxyman on 7/13/26.
//

import Foundation

struct GRPCEventPackage: Codable, Serializable {

    enum EventType: String, Codable {
        case callStarted
        case attemptStarted
        case streamCreated
        case requestMetadata
        case requestMessage
        case requestFinished
        case responseMetadata
        case responseMessage
        case responseStatus
        case attemptFinished
        case callFinished
    }

    enum Outcome: String, Codable {
        case completed
        case status
        case failed
        case cancelled
    }

    enum RPCType: String, Codable {
        case unary
        case clientStreaming
        case serverStreaming
        case bidirectionalStreaming
        case unknown
    }

    enum PayloadOmissionReason: String, Codable {
        case exceedsSizeLimit
        case bufferLimit
    }

    enum Direction: String, Codable {
        case outbound
        case inbound
    }

    struct MetadataEntry: Codable {
        let key: String
        let stringValue: String?
        let binaryValue: Data?

        init(key: String, stringValue: String) {
            self.key = key
            self.stringValue = stringValue
            self.binaryValue = nil
        }

        init(key: String, binaryValue: [UInt8]) {
            self.key = key
            self.stringValue = nil
            self.binaryValue = Data(binaryValue)
        }
    }

    static let schemaVersion = 1

    let eventID: String
    let version: Int
    let timestamp: TimeInterval
    let eventType: EventType
    let callID: String
    let attemptID: String?
    let attemptNumber: Int?
    let method: String?
    let rpcType: RPCType?
    let remotePeer: String?
    let localPeer: String?
    let metadata: [MetadataEntry]?
    let direction: Direction?
    let sequenceNumber: Int?
    private(set) var payload: Data?
    let payloadSize: Int?
    private(set) var payloadOmissionReason: PayloadOmissionReason?
    let statusCode: Int?
    let statusMessage: String?
    let errorCode: Int?
    let errorMessage: String?
    let outcome: Outcome?

    init(eventType: EventType,
         callID: String,
         attemptID: String? = nil,
         attemptNumber: Int? = nil,
         method: String? = nil,
         rpcType: RPCType? = nil,
         remotePeer: String? = nil,
         localPeer: String? = nil,
         metadata: [MetadataEntry]? = nil,
         direction: Direction? = nil,
         sequenceNumber: Int? = nil,
         payload: Data? = nil,
         payloadSize: Int? = nil,
         payloadOmissionReason: PayloadOmissionReason? = nil,
         statusCode: Int? = nil,
         statusMessage: String? = nil,
         errorCode: Int? = nil,
         errorMessage: String? = nil,
         outcome: Outcome? = nil) {
        self.eventID = UUID().uuidString
        self.version = Self.schemaVersion
        self.timestamp = Date().timeIntervalSince1970
        self.eventType = eventType
        self.callID = callID
        self.attemptID = attemptID
        self.attemptNumber = attemptNumber
        self.method = method
        self.rpcType = rpcType
        self.remotePeer = remotePeer
        self.localPeer = localPeer
        self.metadata = metadata
        self.direction = direction
        self.sequenceNumber = sequenceNumber
        self.payload = payload
        self.payloadSize = payloadSize
        self.payloadOmissionReason = payloadOmissionReason
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.outcome = outcome
    }

    var containsPayload: Bool {
        return payload != nil
    }

    func omittingPayloadBecauseBufferIsFull() -> GRPCEventPackage {
        var copy = self
        copy.payload = nil
        copy.payloadOmissionReason = .bufferLimit
        return copy
    }

    func toData() -> Data? {
        do {
            return try JSONEncoder().encode(self)
        } catch {
            print("[Atlantis][gRPC] Could not encode diagnostics event: \(error)")
            return nil
        }
    }
}
