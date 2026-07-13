//
//  GRPCNetworkInjector.swift
//  Atlantis
//
//  Created by Proxyman on 7/13/26.
//

import Foundation
import GRPCCore

enum GRPCNetworkInjectionController {

    static func start(send: @escaping (GRPCEventPackage) -> Void) {
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            GRPCNetworkInjectionState.shared.start(send: send)
        }
    }

    static func stop() {
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            GRPCNetworkInjectionState.shared.stop()
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private final class GRPCNetworkInjectionState {

    static let shared = GRPCNetworkInjectionState()

    private let lock = NSLock()
    private var activeInjector: GRPCNetworkInjector?

    private init() {}

    func start(send: @escaping (GRPCEventPackage) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard activeInjector == nil else { return }

        let injector = GRPCNetworkInjector(send: send)
        activeInjector = injector
        injector.start()
    }

    func stop() {
        lock.lock()
        let injector = activeInjector
        activeInjector = nil
        lock.unlock()
        injector?.stop()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
final class GRPCNetworkInjector: GRPCClientDiagnosticsObserver, @unchecked Sendable {

    private let lock = NSLock()
    private var registration: GRPCClientDiagnosticsRegistration?
    private var sendPackage: ((GRPCEventPackage) -> Void)?

    init(send: @escaping (GRPCEventPackage) -> Void) {
        sendPackage = send
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        if registration == nil {
            registration = GRPCClientDiagnostics.register(self)
        }
    }

    func stop() {
        lock.lock()
        let registration = self.registration
        self.registration = nil
        sendPackage = nil
        lock.unlock()
        registration?.cancel()
    }

    func observe(_ event: GRPCClientDiagnosticsEvent) {
        switch event {
        case .callStarted(let callID, let descriptor):
            send(GRPCEventPackage(eventType: .callStarted,
                                  callID: callID.atlantisID,
                                  method: descriptor.fullyQualifiedMethod,
                                  rpcType: descriptor.atlantisRPCType))

        case .attemptStarted(let attemptID, let descriptor):
            send(GRPCEventPackage(eventType: .attemptStarted,
                                  callID: attemptID.callID.atlantisID,
                                  attemptID: attemptID.atlantisID,
                                  attemptNumber: attemptID.attempt,
                                  method: descriptor.fullyQualifiedMethod,
                                  rpcType: descriptor.atlantisRPCType))

        case .streamCreated(let attemptID, let context):
            send(GRPCEventPackage(eventType: .streamCreated,
                                  callID: attemptID.callID.atlantisID,
                                  attemptID: attemptID.atlantisID,
                                  attemptNumber: attemptID.attempt,
                                  method: context.descriptor.fullyQualifiedMethod,
                                  rpcType: context.descriptor.atlantisRPCType,
                                  remotePeer: context.remotePeer,
                                  localPeer: context.localPeer))

        case .requestMetadata(let attemptID, let metadata):
            send(GRPCEventPackage(eventType: .requestMetadata,
                                  callID: attemptID.callID.atlantisID,
                                  attemptID: attemptID.atlantisID,
                                  attemptNumber: attemptID.attempt,
                                  metadata: metadata.atlantisEntries))

        case .requestFinished(let attemptID):
            send(GRPCEventPackage(eventType: .requestFinished,
                                  callID: attemptID.callID.atlantisID,
                                  attemptID: attemptID.atlantisID,
                                  attemptNumber: attemptID.attempt))

        case .responseMetadata(let attemptID, let metadata):
            send(GRPCEventPackage(eventType: .responseMetadata,
                                  callID: attemptID.callID.atlantisID,
                                  attemptID: attemptID.atlantisID,
                                  attemptNumber: attemptID.attempt,
                                  metadata: metadata.atlantisEntries))

        case .responseStatus(let attemptID, let status, let trailingMetadata):
            send(GRPCEventPackage(eventType: .responseStatus,
                                  callID: attemptID.callID.atlantisID,
                                  attemptID: attemptID.atlantisID,
                                  attemptNumber: attemptID.attempt,
                                  metadata: trailingMetadata.atlantisEntries,
                                  statusCode: status.code.rawValue,
                                  statusMessage: status.message,
                                  outcome: .status))

        case .attemptFinished(let attemptID, let outcome):
            send(makeAttemptFinishedPackage(attemptID: attemptID, outcome: outcome))

        case .callFinished(let callID, let outcome):
            send(makeCallFinishedPackage(callID: callID, outcome: outcome))

        @unknown default:
            break
        }
    }

    func observe<Bytes: GRPCContiguousBytes>(
        message: borrowing Bytes,
        context: GRPCClientDiagnosticsMessageContext
    ) {
        let eventType: GRPCEventPackage.EventType
        let direction: GRPCEventPackage.Direction
        switch context.direction {
        case .outbound:
            eventType = .requestMessage
            direction = .outbound
        case .inbound:
            eventType = .responseMessage
            direction = .inbound
        @unknown default:
            return
        }

        let payloadSize = message.count
        let payload: Data?
        let omissionReason: GRPCEventPackage.PayloadOmissionReason?
        if payloadSize > NetServiceTransport.MaximumSizePackage {
            payload = nil
            omissionReason = .exceedsSizeLimit
        } else {
            payload = message.withUnsafeBytes { Data($0) }
            omissionReason = nil
        }

        let attemptID = context.attemptID
        send(GRPCEventPackage(eventType: eventType,
                              callID: attemptID.callID.atlantisID,
                              attemptID: attemptID.atlantisID,
                              attemptNumber: attemptID.attempt,
                              direction: direction,
                              sequenceNumber: context.sequenceNumber,
                              payload: payload,
                              payloadSize: payloadSize,
                              payloadOmissionReason: omissionReason))
    }

    private func send(_ package: GRPCEventPackage) {
        lock.lock()
        let sendPackage = self.sendPackage
        lock.unlock()
        sendPackage?(package)
    }

    private func makeAttemptFinishedPackage(
        attemptID: GRPCClientAttemptID,
        outcome: GRPCClientAttemptOutcome
    ) -> GRPCEventPackage {
        switch outcome {
        case .status(let status, let trailingMetadata):
            return GRPCEventPackage(eventType: .attemptFinished,
                                    callID: attemptID.callID.atlantisID,
                                    attemptID: attemptID.atlantisID,
                                    attemptNumber: attemptID.attempt,
                                    metadata: trailingMetadata.atlantisEntries,
                                    statusCode: status.code.rawValue,
                                    statusMessage: status.message,
                                    outcome: .status)
        case .failed(let error):
            return GRPCEventPackage(eventType: .attemptFinished,
                                    callID: attemptID.callID.atlantisID,
                                    attemptID: attemptID.atlantisID,
                                    attemptNumber: attemptID.attempt,
                                    metadata: error.metadata.atlantisEntries,
                                    errorCode: error.code?.rawValue,
                                    errorMessage: error.message,
                                    outcome: .failed)
        case .cancelled:
            return GRPCEventPackage(eventType: .attemptFinished,
                                    callID: attemptID.callID.atlantisID,
                                    attemptID: attemptID.atlantisID,
                                    attemptNumber: attemptID.attempt,
                                    outcome: .cancelled)
        @unknown default:
            return GRPCEventPackage(eventType: .attemptFinished,
                                    callID: attemptID.callID.atlantisID,
                                    attemptID: attemptID.atlantisID,
                                    attemptNumber: attemptID.attempt,
                                    errorMessage: "Unknown gRPC attempt outcome",
                                    outcome: .failed)
        }
    }

    private func makeCallFinishedPackage(
        callID: GRPCClientCallID,
        outcome: GRPCClientCallOutcome
    ) -> GRPCEventPackage {
        switch outcome {
        case .completed:
            return GRPCEventPackage(eventType: .callFinished,
                                    callID: callID.atlantisID,
                                    outcome: .completed)
        case .failed(let error):
            return GRPCEventPackage(eventType: .callFinished,
                                    callID: callID.atlantisID,
                                    metadata: error.metadata.atlantisEntries,
                                    errorCode: error.code?.rawValue,
                                    errorMessage: error.message,
                                    outcome: .failed)
        case .cancelled:
            return GRPCEventPackage(eventType: .callFinished,
                                    callID: callID.atlantisID,
                                    outcome: .cancelled)
        @unknown default:
            return GRPCEventPackage(eventType: .callFinished,
                                    callID: callID.atlantisID,
                                    errorMessage: "Unknown gRPC call outcome",
                                    outcome: .failed)
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private extension GRPCClientCallID {
    var atlantisID: String {
        return String(rawValue)
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private extension GRPCClientAttemptID {
    var atlantisID: String {
        return "\(callID.atlantisID).\(attempt)"
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private extension MethodDescriptor {
    var atlantisRPCType: GRPCEventPackage.RPCType {
        switch type {
        case .unary:
            return .unary
        case .clientStreaming:
            return .clientStreaming
        case .serverStreaming:
            return .serverStreaming
        case .bidirectionalStreaming:
            return .bidirectionalStreaming
        case nil:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private extension Metadata {
    var atlantisEntries: [GRPCEventPackage.MetadataEntry] {
        return map { key, value in
            switch value {
            case .string(let string):
                return GRPCEventPackage.MetadataEntry(key: key, stringValue: string)
            case .binary(let bytes):
                return GRPCEventPackage.MetadataEntry(key: key, binaryValue: bytes)
            }
        }
    }
}
