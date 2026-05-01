//
//  ContentView.swift
//  AtlantisSwiftUIApp
//
//  Created by nghiatran on 23/3/25.
//

import SwiftUI
import Network

struct ContentView: View {
    @State private var responseText = ""

    // Server-Sent Events state
    @State private var sseTask: URLSessionDataTask?
    @State private var sseSession: URLSession?
    @State private var sseDelegate: SSEStreamDelegate?
    @State private var sseStatus = "Disconnected"
    @State private var sseMessages: [String] = []
    @State private var sseBuffer = ""
    @State private var sseEventCount = 0
    @State private var sseDemoServer: LocalSSEDemoServer?
    @State private var sseStreamID = UUID()
    private let sseDemoMaxEvents = 10
    private let sseDemoEventInterval: TimeInterval = 0.5
    
    // WebSocket state
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var webSocketStatus = "Disconnected"
    @State private var webSocketMessages: [String] = []

    private var sseStatusColor: Color {
        switch sseStatus {
        case "Connected":
            return .green
        case "Connecting":
            return .orange
        default:
            return .red
        }
    }
    
    var body: some View {
        VStack {
            Text("Capture HTTPS with Atlantis")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            Text("Open Proxyman app -> Tap belows buttons and see Request/Response on Proxyman")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            ScrollView {
                VStack(spacing: 12) {
                    Button("GET Request with Query") {
                        makeGETRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("POST Request with JSON Body") {
                        makePOSTRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("PUT Request with Form Body") {
                        makePUTRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("PATCH Request with Binary Body") {
                        makePATCHRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("DELETE Request") {
                        makeDELETERequest()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Upload Request with Data") {
                        makeUploadRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Divider()
                        .padding(.vertical, 8)

                    VStack {
                        Text("Server-Sent Events Test")
                            .font(.headline)
                            .padding(.bottom, 4)

                        Text("Status: \(sseStatus)")
                            .font(.caption)
                            .foregroundColor(sseStatusColor)

                        HStack {
                            Button(sseStatus == "Disconnected" ? "Start SSE Demo" : "Restart SSE Demo") {
                                startSSETest()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(sseStatus == "Connecting")

                            Button("Stop SSE Demo") {
                                stopSSETest()
                            }
                            .buttonStyle(.bordered)
                            .disabled(sseTask == nil)
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)
                    
                    VStack {
                        Text("WebSocket Test")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Text("Status: \(webSocketStatus)")
                            .font(.caption)
                            .foregroundColor(webSocketStatus == "Connected" ? .green : 
                                           webSocketStatus == "Connecting" ? .orange : .red)
                        
                        Button("WebSocket Test (Auto Demo)") {
                            startWebSocketTest()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(webSocketStatus == "Connecting")
                    }
                }
                .padding()
                
                Divider()
                
                if responseText.isEmpty && sseMessages.isEmpty && webSocketMessages.isEmpty {
                    Text("Response will appear here")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if !responseText.isEmpty {
                            Text("HTTP Response:")
                                .font(.headline)
                            Text(responseText)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !sseMessages.isEmpty {
                            Text("SSE Events:")
                                .font(.headline)
                            ForEach(Array(sseMessages.enumerated()), id: \.offset) { index, message in
                                Text(message)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        }
                        
                        if !webSocketMessages.isEmpty {
                            Text("WebSocket Messages:")
                                .font(.headline)
                            ForEach(Array(webSocketMessages.enumerated()), id: \.offset) { index, message in
                                Text(message)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .onDisappear {
            stopSSETest(shouldAddMessage: false)
        }
    }
    
    // MARK: - Network Requests
    
    func makeGETRequest() {
        // Create a URL with query parameters
        var components = URLComponents(string: "https://httpbin.proxyman.app/get")!
        components.queryItems = [
            URLQueryItem(name: "param1", value: "value1"),
            URLQueryItem(name: "param2", value: "value2")
        ]
        
        guard let url = components.url else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        performRequest(request, title: "GET Request")
    }
    
    func makePOSTRequest() {
        guard let url = URL(string: "https://httpbin.proxyman.app/post?id=post") else { return }

        // JSON Body
        let jsonBody: [String: Any] = [
            "name": "John Doe",
            "email": "john@example.com",
            "age": 30
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("x-proxyman-value", forHTTPHeaderField: "X-Proxyman-Key")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            performRequest(request, title: "POST Request")
        } catch {
            responseText = "Error creating JSON body: \(error.localizedDescription)"
        }
    }
    
    func makePUTRequest() {
        guard let url = URL(string: "https://httpbin.proxyman.app/put") else { return }
        
        // Form Body
        let formBody = "name=Jane+Doe&email=jane%40example.com&age=28"
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody.data(using: .utf8)
        
        performRequest(request, title: "PUT Request")
    }
    
    func makePATCHRequest() {
        guard let url = URL(string: "https://httpbin.proxyman.app/patch") else { return }
        
        // Binary Body (Sample text as binary)
        let binaryBody = "This is a sample binary content".data(using: .utf8)
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = binaryBody
        
        performRequest(request, title: "PATCH Request")
    }
    
    func makeDELETERequest() {
        guard let url = URL(string: "https://httpbin.proxyman.app/delete") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        performRequest(request, title: "DELETE Request")
    }
    
    func makeUploadRequest() {
        guard let url = URL(string: "https://httpbin.proxyman.app/post") else { return }
        
        // Create sample data to upload
        let uploadData = """
        {
            "message": "This is uploaded data",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "method": "upload"
        }
        """.data(using: .utf8)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        responseText = "Uploading..."
        
        URLSession.shared.uploadTask(with: request, from: uploadData) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.responseText = "Upload Error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.responseText = "No data received from upload"
                    return
                }
                
                if let jsonObject = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    self.responseText = "Upload Request Response:\n\(prettyString)"
                } else if let stringData = String(data: data, encoding: .utf8) {
                    self.responseText = "Upload Request Response:\n\(stringData)"
                } else {
                    self.responseText = "Upload Request Response: Unable to decode response"
                }
            }
        }.resume()
    }

    // MARK: - Server-Sent Events Methods

    func startSSETest() {
        stopSSETest(shouldAddMessage: false)

        sseMessages.removeAll()
        sseBuffer = ""
        sseEventCount = 0
        responseText = ""

        let streamID = UUID()
        sseStreamID = streamID
        sseStatus = "Connecting"
        addSSEMessage("Starting local SSE demo server...")

        do {
            let server = try LocalSSEDemoServer(maxEvents: sseDemoMaxEvents,
                                                eventInterval: sseDemoEventInterval)
            server.onReady = { url in
                DispatchQueue.main.async {
                    guard self.sseStreamID == streamID else { return }
                    self.addSSEMessage("Local SSE server ready")
                    self.startSSERequest(url: url, streamID: streamID)
                }
            }
            server.onError = { error in
                DispatchQueue.main.async {
                    guard self.sseStreamID == streamID else { return }
                    self.addSSEMessage("SSE server error: \(error.localizedDescription)")
                    self.stopSSETest(shouldAddMessage: false)
                }
            }

            sseDemoServer = server
            server.start()
        } catch {
            addSSEMessage("Failed to start SSE demo server: \(error.localizedDescription)")
            sseStatus = "Disconnected"
        }
    }

    private func startSSERequest(url: URL, streamID: UUID) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("AtlantisSwiftUIApp/1.0 (https://github.com/ProxymanApp/atlantis)", forHTTPHeaderField: "User-Agent")

        let delegate = SSEStreamDelegate()
        delegate.onResponse = { response in
            DispatchQueue.main.async {
                guard self.sseStreamID == streamID else { return }
                self.sseStatus = "Connected"
                self.addSSEMessage("Connected (HTTP \(response.statusCode)); expecting 10 events")
            }
        }
        delegate.onData = { data in
            DispatchQueue.main.async {
                guard self.sseStreamID == streamID else { return }
                self.handleSSEData(data)
            }
        }
        delegate.onComplete = { error in
            DispatchQueue.main.async {
                guard self.sseStreamID == streamID else { return }
                self.handleSSECompletion(error)
            }
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 15 * 60

        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)

        sseDelegate = delegate
        sseSession = session
        sseTask = task
        addSSEMessage("Connecting to \(url.absoluteString)")

        task.resume()
    }

    private func stopSSETest(shouldAddMessage: Bool = true) {
        guard sseTask != nil || sseSession != nil || sseDemoServer != nil else { return }

        if shouldAddMessage {
            addSSEMessage("Stopping SSE stream...")
        }

        sseTask?.cancel()
        sseSession?.invalidateAndCancel()
        sseDemoServer?.stop()
        sseTask = nil
        sseSession = nil
        sseDelegate = nil
        sseDemoServer = nil
        sseStreamID = UUID()
        sseStatus = "Disconnected"
    }

    private func handleSSEData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else {
            addSSEMessage("Received \(data.count) SSE bytes")
            return
        }

        // SSE events are separated by a blank line, but chunks can split an event anywhere.
        sseBuffer += chunk
        sseBuffer = sseBuffer.replacingOccurrences(of: "\r\n", with: "\n")

        let parts = sseBuffer.components(separatedBy: "\n\n")
        guard parts.count > 1 else { return }

        sseBuffer = parts.last ?? ""
        for event in parts.dropLast() {
            let trimmedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEvent.isEmpty else { continue }
            guard sseEventCount < sseDemoMaxEvents else { continue }

            sseEventCount += 1
            addSSEMessage("Event \(sseEventCount)/\(sseDemoMaxEvents)\n\(summarizeSSEEvent(trimmedEvent))")

            if sseEventCount >= sseDemoMaxEvents {
                addSSEMessage("SSE demo completed; stopping stream")
                stopSSETest(shouldAddMessage: false)
                break
            }
        }
    }

    private func handleSSECompletion(_ error: Error?) {
        let nsError = error as NSError?
        if nsError?.domain == NSURLErrorDomain && nsError?.code == NSURLErrorCancelled {
            sseStatus = "Disconnected"
            return
        }

        if let error = error {
            addSSEMessage("SSE error: \(error.localizedDescription)")
        } else {
            addSSEMessage("SSE stream completed")
        }

        sseTask = nil
        sseSession = nil
        sseDelegate = nil
        sseStatus = "Disconnected"
    }

    private func summarizeSSEEvent(_ eventText: String) -> String {
        var eventName: String?
        var eventID: String?
        var dataLines: [String] = []
        var comment: String?
        var retry: String?

        for rawLine in eventText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(":") {
                comment = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let field = parts.first.map(String.init) ?? ""
            var value = parts.count > 1 ? String(parts[1]) : ""
            if value.hasPrefix(" ") {
                value.removeFirst()
            }

            switch field {
            case "event":
                eventName = value
            case "id":
                eventID = value
            case "data":
                dataLines.append(value)
            case "retry":
                retry = value
            default:
                break
            }
        }

        if !dataLines.isEmpty {
            return summarizeSSEData(dataLines.joined(separator: "\n"), eventName: eventName, eventID: eventID)
        }

        if let comment = comment, !comment.isEmpty {
            return "comment: \(truncate(comment, maxLength: 180))"
        }

        if let retry = retry, !retry.isEmpty {
            return "retry: \(retry) ms"
        }

        return truncate(eventText, maxLength: 180)
    }

    private func summarizeSSEData(_ dataText: String, eventName: String?, eventID: String?) -> String {
        let label = eventName ?? "message"
        var details = truncate(dataText, maxLength: 180)

        if let data = dataText.data(using: .utf8),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            let wiki = object["wiki"] as? String ?? object["server_name"] as? String
            let title = object["title"] as? String
            let user = object["user"] as? String
            let readableFields = [wiki, title, user].compactMap { $0 }.filter { !$0.isEmpty }
            if !readableFields.isEmpty {
                details = readableFields.joined(separator: " | ")
            }
        }

        if let eventID = eventID, !eventID.isEmpty {
            return "event: \(label)\nid: \(truncate(eventID, maxLength: 80))\n\(details)"
        }

        return "event: \(label)\n\(details)"
    }

    private func addSSEMessage(_ message: String) {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        sseMessages.append("[\(timestamp)] \(message)")

        // Keep the demo lightweight while the stream stays open.
        if sseMessages.count > 20 {
            sseMessages.removeFirst()
        }
    }

    private func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength)) + "..."
    }
    
    // MARK: - WebSocket Methods
    
    func startWebSocketTest() {
        // Clear previous messages
        webSocketMessages.removeAll()
        responseText = ""
        
        guard let url = URL(string: "wss://echo.websocket.org/.ws") else {
            addWebSocketMessage("❌ Invalid WebSocket URL")
            return
        }
        
        // Close existing connection if any
        if let existingTask = webSocketTask {
            existingTask.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
        }
        
        webSocketStatus = "Connecting"
        addWebSocketMessage("🔌 Connecting to WebSocket...")
        
        // Create WebSocket task
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        
        // Start receiving messages
        receiveWebSocketMessage()
        
        // Start connection
        webSocketTask?.resume()
        
        // Monitor connection and start demo sequence
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.checkConnectionAndStartDemo()
        }
    }
    
    private func checkConnectionAndStartDemo() {
        guard webSocketTask != nil else { return }
        
        self.webSocketStatus = "Connected"
        self.addWebSocketMessage("✅ WebSocket connected successfully!")
        self.startAutomaticDemo()
    }
    
    private func startAutomaticDemo() {
        addWebSocketMessage("🚀 Starting automatic demo sequence...")
        
        // 1. Send JSON message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.sendJSONMessage()
        }
        
        // 2. Send text message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.sendTextMessage()
        }
        
        // 3. Send binary message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.sendBinaryMessage()
        }

        // 5. Close connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            self.closeWebSocketConnection()
        }
    }
    
    private func sendJSONMessage() {
        guard let task = webSocketTask, webSocketStatus == "Connected" else {
            addWebSocketMessage("❌ Cannot send JSON: WebSocket not connected")
            return
        }
        
        let jsonObject: [String: Any] = [
            "type": "json",
            "message": "Hello from Atlantis iOS app!",
            "timestamp": Date().timeIntervalSince1970,
            "data": [
                "version": "1.0",
                "platform": "iOS"
            ]
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
            let message = URLSessionWebSocketTask.Message.data(jsonData)
            
            task.send(message) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.addWebSocketMessage("❌ Failed to send JSON: \(error.localizedDescription)")
                        self.webSocketStatus = "Disconnected"
                    } else {
                        self.addWebSocketMessage("📤 Sent JSON message")
                    }
                }
            }
        } catch {
            addWebSocketMessage("❌ Failed to create JSON: \(error.localizedDescription)")
        }
    }
    
    private func sendTextMessage() {
        guard let task = webSocketTask, webSocketStatus == "Connected" else {
            addWebSocketMessage("❌ Cannot send text: WebSocket not connected")
            return
        }
        
        let textMessage = "Hello WebSocket! This is a plain text message from Atlantis iOS app at \(Date())"
        let message = URLSessionWebSocketTask.Message.string(textMessage)
        
        task.send(message) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.addWebSocketMessage("❌ Failed to send text: \(error.localizedDescription)")
                    self.webSocketStatus = "Disconnected"
                } else {
                    self.addWebSocketMessage("📤 Sent text message")
                }
            }
        }
    }
    
    private func sendBinaryMessage() {
        guard let task = webSocketTask, webSocketStatus == "Connected" else {
            addWebSocketMessage("❌ Cannot send binary: WebSocket not connected")
            return
        }
        
        let binaryContent = "Binary data from Atlantis: \(Date().timeIntervalSince1970)"
        guard let binaryData = binaryContent.data(using: .utf8) else {
            addWebSocketMessage("❌ Failed to create binary data")
            return
        }
        
        let message = URLSessionWebSocketTask.Message.data(binaryData)
        
        task.send(message) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.addWebSocketMessage("❌ Failed to send binary: \(error.localizedDescription)")
                    self.webSocketStatus = "Disconnected"
                } else {
                    self.addWebSocketMessage("📤 Sent binary message (\(binaryData.count) bytes)")
                }
            }
        }
    }

    private func closeWebSocketConnection() {
        addWebSocketMessage("🔌 Closing WebSocket connection...")
        
        webSocketTask?.cancel(with: .normalClosure, reason: "Demo completed".data(using: .utf8))
        webSocketTask = nil
        webSocketStatus = "Disconnected"
        
        addWebSocketMessage("✅ WebSocket demo completed!")
    }
    
    private func receiveWebSocketMessage() {
        guard let task = webSocketTask else { return }
        
        task.receive { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.addWebSocketMessage("📥 Received text: \(text)")
                    case .data(let data):
                        let dataSize = data.count
                        if let text = String(data: data, encoding: .utf8) {
                            self.addWebSocketMessage("📥 Received data (\(dataSize) bytes): \(text)")
                        } else {
                            self.addWebSocketMessage("📥 Received binary data (\(dataSize) bytes)")
                        }
                    @unknown default:
                        self.addWebSocketMessage("📥 Received unknown message type")
                    }
                    
                    // Continue receiving messages only if still connected
                    if self.webSocketStatus == "Connected" {
                        self.receiveWebSocketMessage()
                    }
                    
                case .failure(let error):
                    // Check if it's a normal closure
                    if (error as NSError).code == 57 { // Connection lost
                        self.addWebSocketMessage("🔌 WebSocket connection closed")
                        self.webSocketStatus = "Disconnected"
                    } else {
                        self.addWebSocketMessage("❌ Receive error: \(error.localizedDescription)")
                        self.webSocketStatus = "Disconnected"
                    }
                }
            }
        }
    }
    
    private func addWebSocketMessage(_ message: String) {
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        webSocketMessages.append("[\(timestamp)] \(message)")
        
        // Keep only last 20 messages to prevent memory issues
        if webSocketMessages.count > 20 {
            webSocketMessages.removeFirst()
        }
    }
    
    private func performRequest(_ request: URLRequest, title: String) {
        responseText = "Loading..."
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.responseText = "Error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.responseText = "No data received"
                    return
                }
                
                if let jsonObject = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    self.responseText = "\(title) Response:\n\(prettyString)"
                } else if let stringData = String(data: data, encoding: .utf8) {
                    self.responseText = "\(title) Response:\n\(stringData)"
                } else {
                    self.responseText = "\(title) Response: Unable to decode response"
                }
            }
        }.resume()
    }
}

#Preview {
    ContentView()
}

// MARK: - Local SSE Demo Server

private final class LocalSSEDemoServer {
    var onReady: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    private let maxEvents: Int
    private let eventInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.example.sse-server")
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private var isStopped = false

    init(maxEvents: Int, eventInterval: TimeInterval) throws {
        self.maxEvents = maxEvents
        self.eventInterval = eventInterval
        self.listener = try NWListener(using: .tcp, on: .any)

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
    }

    func start() {
        listener.start(queue: queue)
    }

    func stop() {
        queue.async {
            self.isStopped = true
            self.listener.cancel()
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)/sse-demo") else {
                return
            }
            DispatchQueue.main.async {
                self.onReady?(url)
            }
        case .failed(let error):
            DispatchQueue.main.async {
                self.onError?(error)
            }
        default:
            break
        }
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
            if let error {
                DispatchQueue.main.async {
                    self.onError?(error)
                }
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
            if let error {
                DispatchQueue.main.async {
                    self.onError?(error)
                }
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
                if let error {
                    DispatchQueue.main.async {
                        self.onError?(error)
                    }
                    connection.cancel()
                    return
                }

                if index >= self.maxEvents {
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

// MARK: - SSE URLSession Delegate

private final class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    var onResponse: ((HTTPURLResponse) -> Void)?
    var onData: ((Data) -> Void)?
    var onComplete: ((Error?) -> Void)?

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let response = response as? HTTPURLResponse {
            onResponse?(response)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        onData?(data)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        onComplete?(error)
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
