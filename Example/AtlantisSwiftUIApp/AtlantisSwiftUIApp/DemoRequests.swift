//
//  DemoRequests.swift
//  AtlantisSwiftUIApp
//

import Foundation

/// URLSession has two loaders, Atlantis captures both of them
enum URLSessionLoader: String {
    /// The default loader
    case classic
    /// Built on Network framework, when usesClassicLoadingMode is false (iOS 18.4+)
    case new
}

/// The requests of the demos, they return the status code.
/// Every URL has a `demo` query item, so the app knows which demo Atlantis captured
enum DemoRequests {

    private static let baseURL = URL(string: "https://httpbin.proxyman.app")!
    private static let webSocketURL = URL(string: "wss://echo.websocket.org/.ws")!
    /// The Atlantis logo in this repository
    private static let atlantisLogoURL = URL(string: "https://raw.githubusercontent.com/ProxymanApp/atlantis/main/images/atlantis_logo.jpg")!

    /// AsyncImage keeps using it, so it's never invalidated
    static let newLoaderImageSession = makeSession(.new)

    static func makeSession(_ loader: URLSessionLoader,
                            delegate: URLSessionDelegate? = nil,
                            configure: (URLSessionConfiguration) -> Void = { _ in }) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        if #available(iOS 18.4, *) {
            configuration.usesClassicLoadingMode = loader == .classic
        }
        configure(configuration)
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    static func url(_ path: String, demo: String) -> URL {
        return url(baseURL.appendingPathComponent(path), demo: demo)
    }

    /// The image of the downloads and AsyncImage
    static func logoURL(demo: String, queryItems: [URLQueryItem] = []) -> URL {
        return url(atlantisLogoURL, demo: demo, queryItems: queryItems)
    }

    private static func url(_ url: URL, demo: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "demo", value: demo)] + queryItems
        return components.url!
    }

    // MARK: - Data Task

    static func get(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }

        let response = try await send {
            session.dataTask(with: url("get", demo: demo), completionHandler: $0)
        }
        return statusCode(response)
    }

    static func post(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }
        var request = postRequest(url("post", demo: demo))
        request.httpBody = jsonBody(api: "dataTask(with:completionHandler:)", loader: loader)

        let response = try await send {
            session.dataTask(with: request, completionHandler: $0)
        }
        return statusCode(response)
    }

    static func dataTaskWithDelegate(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let delegate = DataTaskDelegate()
        let session = makeSession(loader, delegate: delegate)
        defer { session.finishTasksAndInvalidate() }

        let response = try await delegate.run(URLRequest(url: url("get", demo: demo)), on: session)
        return statusCode(response)
    }

    // MARK: - Upload & Download

    static func uploadData(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }
        let request = postRequest(url("post", demo: demo))
        let body = jsonBody(api: "uploadTask(with:from:)", loader: loader)

        let response = try await send {
            session.uploadTask(with: request, from: body, completionHandler: $0)
        }
        return statusCode(response)
    }

    static func uploadFile(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }
        let request = postRequest(url("post", demo: demo))
        let fileURL = try temporaryFile(jsonBody(api: "uploadTask(with:fromFile:)", loader: loader))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let response = try await send {
            session.uploadTask(with: request, fromFile: fileURL, completionHandler: $0)
        }
        return statusCode(response)
    }

    static func downloadTask(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }
        let url = logoURL(demo: demo)

        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLResponse, Error>) in
            session.downloadTask(with: url) { _, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let response = response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
        return statusCode(response)
    }

    // MARK: - Async/Await

    static func asyncData(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: URLRequest(url: url("get", demo: demo)))
        return statusCode(response)
    }

    static func asyncBytes(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }

        // 5 JSON lines
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url("stream/5", demo: demo)))
        for try await _ in bytes.lines {}
        return statusCode(response)
    }

    static func asyncUploadData(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }
        let body = jsonBody(api: "upload(for:from:)", loader: loader)

        let (_, response) = try await session.upload(for: postRequest(url("post", demo: demo)), from: body)
        return statusCode(response)
    }

    static func asyncUploadFile(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }
        let fileURL = try temporaryFile(jsonBody(api: "upload(for:fromFile:)", loader: loader))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (_, response) = try await session.upload(for: postRequest(url("post", demo: demo)), fromFile: fileURL)
        return statusCode(response)
    }

    static func asyncDownload(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.finishTasksAndInvalidate() }

        let (location, response) = try await session.download(for: URLRequest(url: logoURL(demo: demo)))
        try? FileManager.default.removeItem(at: location)
        return statusCode(response)
    }

    // MARK: - Streaming

    /// A local server sends 5 events, then closes the stream
    static func serverSentEvents(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let server = try LocalSSEDemoServer(maxEvents: 5, eventInterval: 0.2)
        defer { server.stop() }
        var request = URLRequest(url: url(try await server.start(), demo: demo))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let delegate = DataTaskDelegate()
        let session = makeSession(loader, delegate: delegate)
        defer { session.finishTasksAndInvalidate() }

        let response = try await delegate.run(request, on: session)
        return statusCode(response)
    }

    /// echo.websocket.org says hello, then echoes every message
    static func webSocket(_ loader: URLSessionLoader, demo: String) async throws -> Int {
        let session = makeSession(loader)
        defer { session.invalidateAndCancel() }
        let task = session.webSocketTask(with: url(webSocketURL, demo: demo))

        // Don't wait forever, cancelling makes the pending calls throw
        let timeout = Task {
            try await Task.sleep(for: .seconds(15))
            task.cancel()
        }
        defer { timeout.cancel() }

        task.resume()

        // Sent before the connection is open, Atlantis keeps them until the handshake is done
        try await task.send(.string("Hello from Atlantis (\(loader.rawValue) loader)"))
        try await task.send(.data(Data("Binary message from Atlantis".utf8)))
        for _ in 0..<3 {
            _ = try await task.receive()
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 101
        task.cancel(with: .normalClosure, reason: Data("Bye".utf8))
        return statusCode
    }

    // MARK: - iOS 26

    /// HTTP/3 0-RTT. It requires the new loader
    static func earlyData(demo: String) async throws -> Int {
        guard #available(iOS 26.0, *) else {
            throw URLError(.unsupportedURL)
        }
        let session = makeSession(.new) { configuration in
            configuration.enablesEarlyData = true
        }
        defer { session.finishTasksAndInvalidate() }

        let (_, response) = try await session.data(for: URLRequest(url: url("get", demo: demo)))
        return statusCode(response)
    }

    /// Ultra Constrained networks, e.g. satellite
    static func ultraConstrainedNetwork(demo: String) async throws -> Int {
        guard #available(iOS 26.1, *) else {
            throw URLError(.unsupportedURL)
        }
        let session = makeSession(.new) { configuration in
            configuration.allowsUltraConstrainedNetworkAccess = true
        }
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url("get", demo: demo))
        request.allowsUltraConstrainedNetworkAccess = true

        let (_, response) = try await session.data(for: request)
        return statusCode(response)
    }

    // MARK: - Private

    /// Resume the task and wait for its completion handler
    private static func send(_ makeTask: (@escaping @Sendable (Data?, URLResponse?, Error?) -> Void) -> URLSessionTask) async throws -> URLResponse {
        return try await withCheckedThrowingContinuation { continuation in
            makeTask { _, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let response = response {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
    }

    private static func statusCode(_ response: URLResponse) -> Int {
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    private static func postRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func jsonBody(api: String, loader: URLSessionLoader) -> Data {
        let json: [String: Any] = ["message": "Hello from Atlantis",
                                   "api": api,
                                   "loader": loader.rawValue,
                                   "timestamp": Date().timeIntervalSince1970]
        return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
    }

    private static func temporaryFile(_ data: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("atlantis-upload-\(UUID().uuidString).json")
        try data.write(to: fileURL)
        return fileURL
    }
}

/// Run a data task with a delegate
private final class DataTaskDelegate: NSObject, URLSessionDataDelegate {

    private var continuation: CheckedContinuation<URLResponse, Error>?

    func run(_ request: URLRequest, on session: URLSession) async throws -> URLResponse {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else if let response = task.response {
            continuation?.resume(returning: response)
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
        continuation = nil
    }
}
