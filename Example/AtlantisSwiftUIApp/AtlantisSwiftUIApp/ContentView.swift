//
//  ContentView.swift
//  AtlantisSwiftUIApp
//
//  Created by nghiatran on 23/3/25.
//

import SwiftUI

struct ContentView: View {
    @State private var responseText = ""
    
    // WebSocket state
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var webSocketStatus = "Disconnected"
    @State private var webSocketMessages: [String] = []
    
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
                
                if responseText.isEmpty && webSocketMessages.isEmpty {
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
        guard let task = webSocketTask else { return }
        
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

// MARK: - Extensions

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
