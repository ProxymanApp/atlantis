//
//  ContentView.swift
//  AtlantisWatchOSApp Watch App
//
//  Created by nghiatran on 29/10/25.
//

import SwiftUI

struct ContentView: View {
    @State private var outputText: String = "Response will appear here..."
    @State private var isLoading: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title
                Text("HTTP Tester - Proxyman")
                    .font(.headline)
                    .padding(.top, 8)

                // Buttons
                HStack(spacing: 10) {
                    Button(action: {
                        makeGETRequest()
                    }) {
                        Label("GET", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)

                    Button(action: {
                        makePOSTRequest()
                    }) {
                        Label("POST", systemImage: "arrow.up.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                }
                .padding(.horizontal, 4)

                // Loading indicator
                if isLoading {
                    ProgressView()
                        .padding(.vertical, 4)
                }

                // Output text view
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(outputText)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
                .padding(.horizontal, 4)
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - HTTP Requests

    func makeGETRequest() {
        isLoading = true
        outputText = "Loading..."

        guard let url = URL(string: "https://httpbin.proxyman.app/get?name=AppleWatch&platform=watchOS") else {
            outputText = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    outputText = "Error: \(error.localizedDescription)"
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    var result = "Status: \(httpResponse.statusCode)\n\n"

                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []),
                       let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        result += jsonString
                    } else if let data = data,
                              let rawString = String(data: data, encoding: .utf8) {
                        result += rawString
                    }

                    outputText = result
                }
            }
        }.resume()
    }

    func makePOSTRequest() {
        isLoading = true
        outputText = "Loading..."

        guard let url = URL(string: "https://httpbin.proxyman.app/post") else {
            outputText = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonBody: [String: Any] = [
            "device": "Apple Watch",
            "platform": "watchOS",
            "action": "test",
            "timestamp": Date().timeIntervalSince1970
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: jsonBody, options: []) else {
            outputText = "Failed to encode JSON"
            isLoading = false
            return
        }

        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    outputText = "Error: \(error.localizedDescription)"
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    var result = "Status: \(httpResponse.statusCode)\n\n"

                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []),
                       let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        result += jsonString
                    } else if let data = data,
                              let rawString = String(data: data, encoding: .utf8) {
                        result += rawString
                    }

                    outputText = result
                }
            }
        }.resume()
    }
}

#Preview {
    ContentView()
}
