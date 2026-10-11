//
//  LocalSSEDemoServer.swift
//  AtlantisSwiftUIApp
//

import Foundation
import Network

/// Serve Server-Sent Events from this device: a few events, then close the stream
/// The state is only used on `queue`
final class LocalSSEDemoServer: @unchecked Sendable {

    private let maxEvents: Int
    private let eventInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.example.sse-server")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var isStopped = false
    private var startContinuation: CheckedContinuation<URL, Error>?

    init(maxEvents: Int, eventInterval: TimeInterval) throws {
        self.maxEvents = maxEvents
        self.eventInterval = eventInterval

        // Only for this device
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        self.listener = try NWListener(using: parameters, on: .any)

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.listenerStateDidChange(state)
        }
    }

    /// Return the URL of the stream when the server is ready
    func start() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startContinuation = continuation
                self.listener.start(queue: self.queue)
            }
        }
    }

    func stop() {
        queue.async {
            self.isStopped = true
            self.listener.cancel()
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    /// On `queue`
    private func listenerStateDidChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener.port,
               let url = URL(string: "http://127.0.0.1:\(port.rawValue)/sse-demo") {
                startContinuation?.resume(returning: url)
            } else {
                startContinuation?.resume(throwing: URLError(.cannotConnectToHost))
            }
        case .failed(let error), .waiting(let error):
            // Don't wait forever, e.g. the loopback interface isn't available
            startContinuation?.resume(throwing: error)
        case .cancelled:
            startContinuation?.resume(throwing: CancellationError())
        default:
            return
        }
        startContinuation = nil
    }

    private func handle(_ connection: NWConnection) {
        connections.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .cancelled = state {
                self.connections.removeAll { $0 === connection }
            }
        }

        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self, !self.isStopped else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var requestData = buffer
            if let data {
                requestData.append(data)
            }

            // Wait for the HTTP header terminator before writing the SSE response.
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil ||
                requestData.range(of: Data("\n\n".utf8)) != nil {
                self.sendResponseHeaders(on: connection)
            } else {
                self.readRequest(on: connection, buffer: requestData)
            }
        }
    }

    private func sendResponseHeaders(on connection: NWConnection) {
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream; charset=utf-8\r
        Cache-Control: no-cache, no-transform\r
        Connection: close\r
        X-Accel-Buffering: no\r
        \r

        """

        connection.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            self.sendEvent(1, on: connection)
        })
    }

    private func sendEvent(_ index: Int, on connection: NWConnection) {
        guard !isStopped else { return }
        guard index <= maxEvents else {
            connection.cancel()
            return
        }

        queue.asyncAfter(deadline: .now() + eventInterval) { [weak self] in
            guard let self, !self.isStopped else { return }

            let event = self.makeEvent(index)
            connection.send(content: Data(event.utf8), completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil || index >= self.maxEvents {
                    connection.cancel()
                } else {
                    self.sendEvent(index + 1, on: connection)
                }
            })
        }
    }

    private func makeEvent(_ index: Int) -> String {
        let payload: [String: Any] = [
            "index": index,
            "message": "Atlantis SSE demo event \(index)",
            "timestamp": Date().timeIntervalSince1970
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? #"{"message":"Atlantis SSE demo event"}"#
        return "event: atlantis-demo\nid: \(index)\ndata: \(json)\n\n"
    }
}
