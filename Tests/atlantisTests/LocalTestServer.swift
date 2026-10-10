import Foundation
import Network

/// A tiny HTTP/1.1 and WebSocket server running in the test process (Network.framework).
/// It doesn't need the internet or Node.js, so the tests run on all platforms, including the iOS/tvOS/watchOS/visionOS simulators.
///
/// HTTP routes:
/// - `/get`, `/post`, anything else: echo the request as JSON `{"method", "path", "body"}`
/// - `/bytes/<n>`: `n` bytes of binary data
/// - `/status/<code>`: an empty response with the status code
/// - `/redirect`: 302 to `/get?redirected=1`
/// - `/sse`: Server-Sent Events (2 events, chunked), then close
///
/// WebSocket: echo every text and binary message, reply to close
final class LocalTestServer {

    private let httpListener: NWListener
    private let webSocketListener: NWListener
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.tests.local-server")
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init() throws {
        httpListener = try NWListener(using: LocalTestServer.makeParameters(isWebSocket: false), on: .any)
        webSocketListener = try NWListener(using: LocalTestServer.makeParameters(isWebSocket: true), on: .any)
    }

    var httpPort: UInt16 {
        httpListener.port?.rawValue ?? 0
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(httpPort)\(path)")!
    }

    func webSocketURL(_ path: String) -> URL {
        URL(string: "ws://127.0.0.1:\(webSocketListener.port?.rawValue ?? 0)\(path)")!
    }

    func start(timeout: TimeInterval = 5) throws {
        let group = DispatchGroup()
        var failure: Error?
        for listener in [httpListener, webSocketListener] {
            group.enter()
            var isSignaled = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    break
                case .failed(let error):
                    failure = error
                case .cancelled:
                    failure = NWError.posix(.ECANCELED)
                default:
                    return
                }
                if !isSignaled {
                    isSignaled = true
                    group.leave()
                }
            }
        }
        httpListener.newConnectionHandler = { [weak self] connection in
            self?.acceptHTTPConnection(connection)
        }
        webSocketListener.newConnectionHandler = { [weak self] connection in
            self?.acceptWebSocketConnection(connection)
        }
        httpListener.start(queue: queue)
        webSocketListener.start(queue: queue)

        guard group.wait(timeout: .now() + timeout) == .success else {
            throw NWError.posix(.ETIMEDOUT)
        }
        if let failure = queue.sync(execute: { failure }) {
            throw failure
        }
    }

    /// Call it from the test (not from the server queue)
    func stop() {
        httpListener.newConnectionHandler = nil
        webSocketListener.newConnectionHandler = nil
        httpListener.cancel()
        webSocketListener.cancel()
        queue.sync {
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private static func makeParameters(isWebSocket: Bool) -> NWParameters {
        let parameters = NWParameters.tcp
        // Only for this device, it shouldn't trigger the Local Network permission
        parameters.requiredInterfaceType = .loopback
        if isWebSocket {
            let options = NWProtocolWebSocket.Options()
            options.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        }
        return parameters
    }

    private func track(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}

// MARK: - HTTP

extension LocalTestServer {

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func acceptHTTPConnection(_ connection: NWConnection) {
        track(connection)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buffer = buffer
            if let data = data {
                buffer.append(data)
            }
            if let request = LocalTestServer.parseRequest(buffer) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.readRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let path = request.path.components(separatedBy: "?")[0]
        switch path {
        case "/sse":
            sendServerSentEvents(on: connection)
        case "/redirect":
            send(status: 302, headers: ["Location": "/get?redirected=1"], body: Data(), on: connection)
        case _ where path.hasPrefix("/status/"):
            send(status: Int(path.dropFirst("/status/".count)) ?? 500, headers: [:], body: Data(), on: connection)
        case _ where path.hasPrefix("/bytes/"):
            let count = Int(path.dropFirst("/bytes/".count)) ?? 0
            let body = Data((0..<count).map { UInt8($0 % 251) })
            send(status: 200, headers: ["Content-Type": "application/octet-stream"], body: body, on: connection)
        default:
            let json: [String: String] = ["method": request.method,
                                          "path": request.path,
                                          "body": String(decoding: request.body, as: UTF8.self)]
            let body = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
            send(status: 200, headers: ["Content-Type": "application/json"], body: body, on: connection)
        }
    }

    private func send(status: Int, headers: [String: String], body: Data, on connection: NWConnection) {
        var headers = headers
        headers["Content-Length"] = "\(body.count)"
        headers["Connection"] = "close"
        var response = Data(LocalTestServer.head(status: status, headers: headers).utf8)
        response.append(body)
        connection.send(content: response, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendServerSentEvents(on connection: NWConnection) {
        let head = LocalTestServer.head(status: 200, headers: ["Content-Type": "text/event-stream",
                                                               "Cache-Control": "no-cache",
                                                               "Transfer-Encoding": "chunked",
                                                               "Connection": "close"])
        let events = ["event: greeting\nid: 1\ndata: hello-atlantis\n\n",
                      "event: greeting\nid: 2\ndata: goodbye-atlantis\n\n"]
        // Keep the stream open between the events
        connection.send(content: Data(head.utf8), contentContext: .defaultStream, isComplete: false, completion: .idempotent)
        for (index, event) in events.enumerated() {
            queue.asyncAfter(deadline: .now() + .milliseconds(50 * (index + 1))) {
                let chunk = String(event.utf8.count, radix: 16) + "\r\n" + event + "\r\n"
                connection.send(content: Data(chunk.utf8), contentContext: .defaultStream, isComplete: false, completion: .idempotent)
            }
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(50 * (events.count + 1))) {
            connection.send(content: Data("0\r\n\r\n".utf8), contentContext: .defaultStream, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func head(status: Int, headers: [String: String]) -> String {
        var head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
        for (key, value) in headers {
            head += "\(key): \(value)\r\n"
        }
        return head + "\r\n"
    }

    /// Return the request when its head and its body (Content-Length or chunked) are fully received
    static func parseRequest(_ buffer: Data) -> Request? {
        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        var lines = String(decoding: buffer[buffer.startIndex..<headEnd.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().components(separatedBy: " ")
        guard requestLine.count >= 2 else {
            return nil
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].lowercased()
            headers[key] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        }

        let rest = Data(buffer[headEnd.upperBound...])
        let body: Data
        if let length = headers["content-length"].flatMap(Int.init) {
            guard rest.count >= length else { return nil }
            body = rest.prefix(length)
        } else if headers["transfer-encoding"]?.lowercased() == "chunked" {
            guard let decoded = decodeChunkedBody(rest) else { return nil }
            body = decoded
        } else {
            body = Data()
        }
        return Request(method: requestLine[0], path: requestLine[1], headers: headers, body: body)
    }

    private static func decodeChunkedBody(_ data: Data) -> Data? {
        var body = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while let lineEnd = data.range(of: crlf, in: index..<data.endIndex) {
            let sizeLine = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
            guard let size = Int(sizeLine.components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces), radix: 16) else {
                return nil
            }
            index = lineEnd.upperBound
            if size == 0 {
                return body
            }
            guard data.distance(from: index, to: data.endIndex) >= size + crlf.count else {
                return nil
            }
            let chunkEnd = data.index(index, offsetBy: size)
            body.append(data[index..<chunkEnd])
            index = data.index(chunkEnd, offsetBy: crlf.count)
        }
        return nil
    }
}

// MARK: - WebSocket

extension LocalTestServer {

    private func acceptWebSocketConnection(_ connection: NWConnection) {
        track(connection)
        receiveWebSocketMessage(on: connection)
    }

    private func receiveWebSocketMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self = self else { return }
            guard error == nil else {
                connection.cancel()
                return
            }
            guard let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata else {
                self.receiveWebSocketMessage(on: connection)
                return
            }

            switch metadata.opcode {
            case .text, .binary:
                // Echo
                let reply = NWProtocolWebSocket.Metadata(opcode: metadata.opcode)
                let context = NWConnection.ContentContext(identifier: "echo", metadata: [reply])
                connection.send(content: content, contentContext: context, isComplete: true, completion: .idempotent)
                self.receiveWebSocketMessage(on: connection)
            case .close:
                let reply = NWProtocolWebSocket.Metadata(opcode: .close)
                reply.closeCode = metadata.closeCode
                let context = NWConnection.ContentContext(identifier: "close", metadata: [reply])
                connection.send(content: nil, contentContext: context, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            default:
                self.receiveWebSocketMessage(on: connection)
            }
        }
    }
}
