//
//  ContentView.swift
//  AtlantisSwiftUIApp
//
//  Created by nghiatran on 23/3/25.
//

import SwiftUI

struct ContentView: View {
    @State private var responseText = ""
    
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
                }
                .padding()
                
                Divider()
                
                if responseText.isEmpty {
                    Text("Response will appear here")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    Text(responseText)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
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
