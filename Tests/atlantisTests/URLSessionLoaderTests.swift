import Foundation
import ObjectiveC
import XCTest
@testable import Atlantis

// MARK: - Loaders

/// URLSession has two loaders. Atlantis must capture the traffic from both of them
enum URLSessionLoader: String {

    /// The default loader, the tasks talk to __NSCFURLLocalSessionConnection
    case classic

    /// The loader built on Network.framework (NWURLSession, NWURLSessionTask): iOS 18.4+, macOS 15.4+, tvOS 18.4+, watchOS 11.4+, visionOS 2.4+
    /// URLSession uses it when `usesClassicLoadingMode` is false. It's required by iOS 26 APIs, e.g. `enablesEarlyData`
    case network

    static var isNetworkLoaderAvailable: Bool {
        if #available(iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *) {
            return true
        }
        return false
    }
}

// MARK: - Capture tests

/// Every URLSession API, with the classic loader.
/// `NetworkLoaderCaptureTests` runs the same tests with the new loader
class URLSessionCaptureTests: XCTestCase {

    class var loader: URLSessionLoader {
        return .classic
    }

    private(set) var server: LocalTestServer!
    private(set) var transporter: CapturingTransporter!
    private let sessionsLock = NSLock()
    private var sessions: [URLSession] = []
    private var watchdog: DispatchWorkItem?

    override func setUpWithError() throws {
        try super.setUpWithError()
        if Self.loader == .network, !URLSessionLoader.isNetworkLoaderAvailable {
            throw XCTSkip("The new URLSession loader requires iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4 or visionOS 2.4")
        }

        server = try LocalTestServer()
        try server.start()

        transporter = CapturingTransporter()
        Atlantis.setIsRunningOniOSPlayground(true)
        Atlantis.setEnableTransportLayer(true)
        Atlantis.setTransporterForTesting(transporter)
        Atlantis.start()

        // A broken test must fail, not hang
        let watchdog = DispatchWorkItem { [weak self] in
            self?.cancelRunningTasks()
        }
        self.watchdog = watchdog
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
    }

    override func tearDown() {
        watchdog?.cancel()
        watchdog = nil
        sessionsLock.lock()
        sessions.forEach { $0.invalidateAndCancel() }
        sessions.removeAll()
        sessionsLock.unlock()
        Atlantis.stop()
        server?.stop()
        server = nil
        transporter = nil
        super.tearDown()
    }

    // MARK: - Data Task

    func testDataTaskWithCompletionHandler() async throws {
        let url = uniqueURL("/get")
        let session = makeSession()

        let (data, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.dataTask(with: url) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: data)
    }

    func testDataTaskWithDelegate() async throws {
        let url = uniqueURL("/get")
        let delegate = TaskDelegate()
        let session = makeSession(delegate: delegate)

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            delegate.onComplete = { continuation.resume(returning: $0) }
            session.dataTask(with: url).resume()
        }
        XCTAssertNil(error)

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: delegate.receivedData)
    }

    func testPostDataTaskCapturesRequestBody() async throws {
        let url = uniqueURL("/post")
        let body = Data("post-body-\(Self.loader)".utf8)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        let session = makeSession()

        let (data, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.dataTask(with: request) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "POST", requestBody: body, responseBody: data)
    }

    func testAsyncData() async throws {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("async/await URLSession requires iOS 15")
        }
        let url = uniqueURL("/get")

        let (data, _) = try await makeSession().data(for: URLRequest(url: url))

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: data)
    }

    func testAsyncBytes() async throws {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("async/await URLSession requires iOS 15")
        }
        let url = uniqueURL("/bytes/2048")

        let (bytes, _) = try await makeSession().bytes(for: URLRequest(url: url))
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: data)
        XCTAssertEqual(package.responseBodyData.count, 2048)
    }

    func testLargeResponseBodyDeliveredInChunks() async throws {
        let url = uniqueURL("/bytes/\(1024 * 1024)")
        let session = makeSession()

        let (data, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.dataTask(with: url) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: data)
        XCTAssertEqual(package.responseBodyData.count, 1024 * 1024)
    }

    func testEmptyResponse() async throws {
        let url = uniqueURL("/status/204")
        let session = makeSession()

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.dataTask(with: url) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }

        let package = try await capturedTraffic(for: url)
        XCTAssertEqual(package.response?.statusCode, 204)
        XCTAssertNil(package.error)
        XCTAssertNotNil(package.endAt)
        XCTAssertTrue(package.responseBodyData.isEmpty)
    }

    func testRedirectCapturesFinalRequest() async throws {
        let url = uniqueURL("/redirect")
        let session = makeSession()

        let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.dataTask(with: url) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }
        XCTAssertEqual(response.url?.query, "redirected=1")

        let package = try await capturedTraffic(for: server.url("/get?redirected=1"))
        assertSuccess(package, method: "GET", responseBody: data)
    }

    func testConnectionErrorIsCaptured() async throws {
        // Nothing listens on port 1
        let url = URL(string: "http://127.0.0.1:1/get?id=\(UUID().uuidString)")!
        let session = makeSession()

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            session.dataTask(with: url) { _, _, error in
                continuation.resume(returning: error)
            }.resume()
        }
        XCTAssertNotNil(error)

        let package = try await capturedTraffic(for: url)
        XCTAssertNil(package.response)
        XCTAssertEqual(package.error?.code, NSURLErrorCannotConnectToHost)
        XCTAssertNotNil(package.endAt)
    }

    // MARK: - Upload

    func testUploadFromDataWithCompletionHandler() async throws {
        let url = uniqueURL("/post")
        let body = Data("upload-data-\(Self.loader)".utf8)
        let session = makeSession()

        let (data, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.uploadTask(with: postRequest(url), from: body) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }

        // The new loader calls the private upload func from this one, the body must not be duplicated
        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "POST", requestBody: body, responseBody: data)
    }

    func testUploadFromDataWithDelegate() async throws {
        let url = uniqueURL("/post")
        let body = Data("upload-data-delegate-\(Self.loader)".utf8)
        let delegate = TaskDelegate()
        let session = makeSession(delegate: delegate)

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<Error?, Never>) in
            delegate.onComplete = { continuation.resume(returning: $0) }
            session.uploadTask(with: postRequest(url), from: body).resume()
        }
        XCTAssertNil(error)

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "POST", requestBody: body, responseBody: delegate.receivedData)
    }

    func testUploadFromFileWithCompletionHandler() async throws {
        let url = uniqueURL("/post")
        let body = Data("upload-file-\(Self.loader)".utf8)
        let fileURL = try temporaryFile(body)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let session = makeSession()

        let (data, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.uploadTask(with: postRequest(url), fromFile: fileURL) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "POST", requestBody: body, responseBody: data)
    }

    /// upload(for:from:) uses a private func (_uploadTaskWithRequest:fromData:delegate:completionHandler:)
    func testAsyncUploadFromData() async throws {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("async/await URLSession requires iOS 15")
        }
        let url = uniqueURL("/post")
        let body = Data("async-upload-data-\(Self.loader)".utf8)

        let (data, _) = try await makeSession().upload(for: postRequest(url), from: body)

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "POST", requestBody: body, responseBody: data)
    }

    /// upload(for:fromFile:) uses a private func (_uploadTaskWithRequest:fromFile:delegate:completionHandler:)
    func testAsyncUploadFromFile() async throws {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("async/await URLSession requires iOS 15")
        }
        let url = uniqueURL("/post")
        let body = Data("async-upload-file-\(Self.loader)".utf8)
        let fileURL = try temporaryFile(body)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (data, _) = try await makeSession().upload(for: postRequest(url), fromFile: fileURL)

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "POST", requestBody: body, responseBody: data)
    }

    // MARK: - Download

    func testDownloadTaskWithCompletionHandler() async throws {
        let url = uniqueURL("/bytes/64")
        let session = makeSession()

        let downloaded = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            session.downloadTask(with: url) { location, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: location.flatMap { try? Data(contentsOf: $0) } ?? Data())
                }
            }.resume()
        }

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: downloaded)
        XCTAssertEqual(package.responseBodyData.count, 64)
    }

    func testAsyncDownload() async throws {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("async/await URLSession requires iOS 15")
        }
        let url = uniqueURL("/bytes/128")

        let (location, _) = try await makeSession().download(for: URLRequest(url: url))
        let downloaded = try Data(contentsOf: location)

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: downloaded)
        XCTAssertEqual(package.responseBodyData.count, 128)
    }

    // MARK: - Server-Sent Events

    func testServerSentEvents() async throws {
        let url = uniqueURL("/sse")
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let session = makeSession()

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.dataTask(with: request) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }

        let messages = await waitForStreamMessages(for: url) { messages in
            messages.contains { $0.messageType == .sendCloseMessage }
        }
        let package = try await capturedTraffic(for: url)
        XCTAssertEqual(package.packageType, .websocket, "SSE uses the WebSocket-compatible package type")
        XCTAssertEqual(package.response?.statusCode, 200)
        XCTAssertEqual(messages.filter { $0.messageType == .receive }.compactMap(\.stringValue),
                       ["event: greeting\nid: 1\ndata: hello-atlantis",
                        "event: greeting\nid: 2\ndata: goodbye-atlantis"])
        XCTAssertEqual(messages.last?.messageType, .sendCloseMessage)
    }

    // MARK: - WebSocket

    func testWebSocket() async throws {
        let url = server.webSocketURL("/chat?id=\(UUID().uuidString)")
        let task = makeSession().webSocketTask(with: url)
        task.resume()

        // Send right after resume(), before the handshake is done
        try await task.send(.string("hello-atlantis"))
        try await task.send(.data(Data([0x01, 0x02, 0x03])))
        _ = try await task.receive()
        _ = try await task.receive()
        // Atlantis records the ping when it's sent, the pong doesn't matter
        task.sendPing { _ in }
        task.cancel(with: .normalClosure, reason: Data("bye".utf8))

        let messages = await waitForStreamMessages(for: url) { $0.count >= 6 }
        let package = try await capturedTraffic(for: url)
        XCTAssertEqual(package.packageType, .websocket)
        XCTAssertEqual(package.response?.statusCode, 101)
        XCTAssertNil(package.error)

        // Every message, in order. The first ones are sent before the handshake
        XCTAssertEqual(messages.map(\.messageType), [.send, .send, .receive, .receive, .pingPong, .sendCloseMessage])
        guard messages.count == 6 else { return }
        XCTAssertEqual(messages[0].stringValue, "hello-atlantis")
        XCTAssertEqual(messages[1].dataValue, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(messages[2].stringValue, "hello-atlantis")
        XCTAssertEqual(messages[3].dataValue, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(messages[5].stringValue, "\(URLSessionWebSocketTask.CloseCode.normalClosure.rawValue)")
        XCTAssertEqual(messages[5].dataValue, Data("bye".utf8))
    }

    func testWebSocketHandshakeFailureIsCaptured() async throws {
        // The classic loader reports it when CFNetwork finishes the HTTP response, it doesn't always happen on iOS 27 (about 1 in 20)
        guard Self.loader == .network else {
            throw XCTSkip("The classic loader might not finish the response of a refused WebSocket upgrade")
        }

        // The HTTP server doesn't upgrade the connection
        let url = URL(string: "ws://127.0.0.1:\(server.httpPort)/get?id=\(UUID().uuidString)")!
        let task = makeSession().webSocketTask(with: url)
        task.resume()

        do {
            _ = try await task.receive()
            XCTFail("The handshake should fail")
        } catch {
            // Expected
        }

        // The server answered 200 instead of 101
        let package = try await capturedTraffic(for: url)
        XCTAssertEqual(package.packageType, .websocket)
        XCTAssertEqual(package.response?.statusCode, 200)
    }

    // MARK: - URLProtocol

    func testCustomURLProtocolIsCaptured() async throws {
        let url = uniqueURL(MockURLProtocol.path)
        let session = makeSession { configuration in
            configuration.protocolClasses = [MockURLProtocol.self]
        }

        let (data, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            session.dataTask(with: url) { data, response, error in
                continuation.resume(with: Self.result(data, response, error))
            }.resume()
        }
        XCTAssertEqual(data, MockURLProtocol.body)

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: data)
    }

    func testIgnoredURLProtocolIsNotCaptured() async throws {
        Atlantis.setIgnoreProtocols([MockURLProtocol.self])
        defer { Atlantis.setIgnoreProtocols([]) }
        let ignoredURL = uniqueURL(MockURLProtocol.path)
        let url = uniqueURL("/get")
        let session = makeSession { configuration in
            configuration.protocolClasses = [MockURLProtocol.self]
        }

        for requestURL in [ignoredURL, url] {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                session.dataTask(with: requestURL) { data, response, error in
                    continuation.resume(with: Self.result(data, response, error))
                }.resume()
            }
        }

        // MockURLProtocol doesn't handle /get
        _ = try await capturedTraffic(for: url)
        XCTAssertTrue(transporter.trafficPackages(for: ignoredURL).isEmpty, "[\(Self.loader)] The request from the ignored URLProtocol is captured")
    }

    // MARK: - iOS 26 / iOS 27

    /// iOS 26: HTTP/3 0-RTT early data. Only the new loader supports it
    func testEnablesEarlyData() async throws {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) else {
            throw XCTSkip("enablesEarlyData requires iOS 26")
        }
        let url = uniqueURL("/get")
        let session = makeSession { configuration in
            configuration.enablesEarlyData = true
        }

        let (data, _) = try await session.data(for: URLRequest(url: url))

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "GET", responseBody: data)
    }

    /// iOS 26.1: Ultra Constrained networks (e.g. satellite)
    func testAllowsUltraConstrainedNetworkAccess() async throws {
        guard #available(iOS 26.1, macOS 26.1, tvOS 26.1, watchOS 26.1, visionOS 26.1, *) else {
            throw XCTSkip("allowsUltraConstrainedNetworkAccess requires iOS 26.1")
        }
        let url = uniqueURL("/post")
        let body = Data("ultra-constrained-\(Self.loader)".utf8)
        let session = makeSession { configuration in
            configuration.allowsUltraConstrainedNetworkAccess = true
        }
        var request = postRequest(url)
        request.allowsUltraConstrainedNetworkAccess = true

        let (data, _) = try await session.upload(for: request, from: body)

        let package = try await capturedTraffic(for: url)
        assertSuccess(package, method: "POST", requestBody: body, responseBody: data)
    }

    // MARK: - Helpers

    func makeSession(delegate: URLSessionDelegate? = nil, configure: (URLSessionConfiguration) -> Void = { _ in }) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        if #available(iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *) {
            configuration.usesClassicLoadingMode = Self.loader == .classic
        }
        configure(configuration)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        sessionsLock.lock()
        sessions.append(session)
        sessionsLock.unlock()
        return session
    }

    /// Cancelling makes the completion handlers and the async funcs return, so the test can fail
    private func cancelRunningTasks() {
        sessionsLock.lock()
        let sessions = self.sessions
        sessionsLock.unlock()
        for session in sessions {
            session.getAllTasks { tasks in
                for task in tasks where task.state != .completed {
                    let message = "[\(Self.loader)] ⚠️ \(self.name): cancel the stuck task \(task) state=\(task.state.rawValue) sent=\(task.countOfBytesSent) received=\(task.countOfBytesReceived) response=\(String(describing: (task.response as? HTTPURLResponse)?.statusCode))\n"
                    FileHandle.standardError.write(Data(message.utf8))
                    task.cancel()
                }
            }
        }
    }

    private func uniqueURL(_ path: String) -> URL {
        return server.url("\(path)?id=\(UUID().uuidString)")
    }

    private func postRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: fileURL)
        return fileURL
    }

    private static func result(_ data: Data?, _ response: URLResponse?, _ error: Error?) -> Result<(Data, URLResponse), Error> {
        if let error = error {
            return .failure(error)
        }
        guard let response = response else {
            return .failure(URLError(.badServerResponse))
        }
        return .success((data ?? Data(), response))
    }

    /// Wait for the traffic of the URL, and make sure it's captured exactly once
    private func capturedTraffic(for url: URL, file: StaticString = #filePath, line: UInt = #line) async throws -> TrafficPackage {
        let packages = await waitFor { () -> [TrafficPackage]? in
            let packages = self.transporter.trafficPackages(for: url)
            return packages.isEmpty ? nil : packages
        }
        guard let package = packages?.first else {
            XCTFail("[\(Self.loader)] Atlantis didn't capture \(url)", file: file, line: line)
            throw URLError(.timedOut)
        }

        // Late callbacks must not report it twice
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(transporter.trafficPackages(for: url).count, 1, "[\(Self.loader)] \(url) is captured more than once", file: file, line: line)
        return package
    }

    private func waitForStreamMessages(for url: URL, until condition: @escaping ([CapturingTransporter.StreamMessage]) -> Bool) async -> [CapturingTransporter.StreamMessage] {
        let messages = await waitFor { () -> [CapturingTransporter.StreamMessage]? in
            let messages = self.transporter.streamMessages(for: url)
            return condition(messages) ? messages : nil
        }
        return messages ?? transporter.streamMessages(for: url)
    }

    private func waitFor<T>(timeout: TimeInterval = 10, _ value: () -> T?) async -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = value() {
                return value
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return value()
    }

    private func assertSuccess(_ package: TrafficPackage,
                               method: String,
                               requestBody: Data? = nil,
                               responseBody: Data,
                               file: StaticString = #filePath,
                               line: UInt = #line) {
        let loader = Self.loader
        XCTAssertEqual(package.packageType, .http, "[\(loader)]", file: file, line: line)
        XCTAssertEqual(package.request.method, method, "[\(loader)]", file: file, line: line)
        XCTAssertEqual(package.response?.statusCode, 200, "[\(loader)]", file: file, line: line)
        XCTAssertNil(package.error, "[\(loader)]", file: file, line: line)
        XCTAssertNotNil(package.endAt, "[\(loader)]", file: file, line: line)
        if let requestBody = requestBody {
            XCTAssertEqual(package.request.body, requestBody, "[\(loader)] Request body", file: file, line: line)
        }
        XCTAssertFalse(responseBody.isEmpty, "[\(loader)] Empty response from the server", file: file, line: line)
        XCTAssertEqual(package.responseBodyData, responseBody, "[\(loader)] Response body", file: file, line: line)
    }
}

final class NetworkLoaderCaptureTests: URLSessionCaptureTests {

    override class var loader: URLSessionLoader {
        return .network
    }
}

// MARK: - Private APIs

/// Atlantis swizzles private methods. If a new OS changes them, these tests tell exactly what is changed
final class URLSessionPrivateAPITests: XCTestCase {

    func testNetworkLoaderIsUsedWhenClassicLoadingModeIsOff() throws {
        guard #available(iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *) else {
            throw XCTSkip("The new URLSession loader requires iOS 18.4")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.usesClassicLoadingMode = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "http://127.0.0.1:1")!

        let tasks: [(URLSessionTask, String)] = [(session.dataTask(with: url), "NWURLSessionDataTask"),
                                                 (session.uploadTask(with: URLRequest(url: url), from: Data()), "NWURLSessionUploadTask"),
                                                 (session.downloadTask(with: url), "NWURLSessionDownloadTask"),
                                                 (session.webSocketTask(with: URL(string: "ws://127.0.0.1:1")!), "NWURLSessionWebSocketTask")]
        XCTAssertEqual(NSStringFromClass(type(of: session)), "NWURLSession")
        for (task, className) in tasks {
            XCTAssertEqual(NSStringFromClass(type(of: task)), className)
            // NWURLSessionTask doesn't inherit from NSURLSessionTask (macOS, iOS), but it answers isKind(of:), so `as? URLSessionTask` works
            XCTAssertTrue(task.isKind(of: URLSessionTask.self), className)
        }
        XCTAssertTrue(tasks[3].0.isWebSocketTask)
        // Atlantis.setIgnoreProtocols(_:) reads the session with KVC, there is no `session` getter but a `_session` ivar
        XCTAssertTrue(tasks[0].0.value(forKey: "session") is URLSession)
    }

    func testNetworkLoaderSelectorsExist() throws {
        guard #available(iOS 18.4, macOS 15.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *) else {
            throw XCTSkip("The new URLSession loader requires iOS 18.4")
        }
        assertMethod("NWURLSession", "uploadTaskWithRequest:fromData:", encoding: "@@:@@")
        assertMethod("NWURLSession", "uploadTaskWithRequest:fromData:completionHandler:", encoding: "@@:@@@?")
        assertMethod("NWURLSession", "uploadTaskWithRequest:fromFile:", encoding: "@@:@@")
        assertMethod("NWURLSession", "uploadTaskWithRequest:fromFile:completionHandler:", encoding: "@@:@@@?")
        assertMethod("NWURLSession", "_uploadTaskWithRequest:fromData:delegate:completionHandler:", encoding: "@@:@@@@?")
        assertMethod("NWURLSession", "_uploadTaskWithRequest:fromFile:delegate:completionHandler:", encoding: "@@:@@@@?")

        assertMethod("NWURLSessionTask", "resume", encoding: "v@:")
        assertMethod("NWURLSessionTask", "loaderConnectedWithHTTPConnectionMetadata:CNAMEChain:unlistedTracker:", encoding: "v@:@@@")

        for consumer in ["NWURLSessionResponseConsumerDataCompletionHandler",
                         "NWURLSessionResponseConsumerDataDelegate",
                         "NWURLSessionResponseConsumerDownload"] {
            assertMethod(consumer, "task:deliverResponse:completionHandler:", encoding: "v@:@@@?")
            assertMethod(consumer, "task:deliverData:complete:error:completionHandler:", encoding: "v@:@@B@@?")
        }

        assertMethod("NWURLSessionWebSocketTask", "sendMessage:completionHandler:", encoding: "v@:@@?")
        assertMethod("NWURLSessionWebSocketTask", "receiveMessageWithCompletionHandler:", encoding: "v@:@?")
        assertMethod("NWURLSessionWebSocketTask", "sendPingWithPongReceiveHandler:", encoding: "v@:@?")
        assertMethod("NWURLSessionWebSocketTask", "cancelWithCloseCode:reason:", encoding: "v@:q@")

        // Optional, macOS 15 / iOS 18 don't have it
        if #available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
            assertMethod("NWURLSessionWebSocketTask", "completeTaskWithError:retryable:", encoding: "v@:@B")
        }
    }

    func testClassicLoaderAsyncUploadSelectorsExist() throws {
        guard #available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *) else {
            throw XCTSkip("async/await URLSession requires iOS 15")
        }
        assertMethod("NSURLSession", "_uploadTaskWithRequest:fromData:delegate:completionHandler:", encoding: "@@:@@@@?")
        assertMethod("NSURLSession", "_uploadTaskWithRequest:fromFile:delegate:completionHandler:", encoding: "@@:@@@@?")
    }

    /// The encoding is compared without the offsets. BOOL might be encoded as `c` and NSInteger as `i` or `l` on some architectures
    private func assertMethod(_ className: String, _ selectorName: String, encoding: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let cls = NSClassFromString(className) else {
            XCTFail("Missing class \(className)", file: file, line: line)
            return
        }
        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getInstanceMethod(cls, selector),
              let typeEncoding = method_getTypeEncoding(method) else {
            XCTFail("Missing -[\(className) \(selectorName)]", file: file, line: line)
            return
        }
        let normalized = String(cString: typeEncoding)
            .filter { !$0.isNumber }
            .replacingOccurrences(of: "c", with: "B")
            .replacingOccurrences(of: "i", with: "q")
            .replacingOccurrences(of: "l", with: "q")
        XCTAssertEqual(normalized, encoding, "-[\(className) \(selectorName)] has a new signature", file: file, line: line)
    }
}

// MARK: - Test doubles

/// Record what Atlantis sends to Proxyman
final class CapturingTransporter: Transporter {

    struct StreamMessage {
        let url: String
        let messageType: WebsocketMessagePackage.MessageType
        let stringValue: String?
        let dataValue: Data?
    }

    private struct Envelope: Decodable {
        let messageType: Message.MessageType
        let content: Data?
    }

    private struct StreamContent: Decodable {
        struct Request: Decodable {
            let url: String
        }
        struct MessagePackage: Decodable {
            let messageType: WebsocketMessagePackage.MessageType
            let stringValue: String?
            let dataValue: Data?
        }
        let request: Request
        let websocketMessagePackage: MessagePackage?
    }

    private let lock = NSLock()
    private var allTrafficPackages: [TrafficPackage] = []
    private var allStreamMessages: [StreamMessage] = []

    func start(_ config: Configuration) {
        // No-op: avoid Bonjour/network in tests.
    }

    func stop() {
        // No-op
    }

    func send(package: Serializable) {
        guard let data = package.toData(),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let content = envelope.content else {
            return
        }

        lock.lock()
        defer { lock.unlock() }
        switch envelope.messageType {
        case .traffic:
            if let package = try? JSONDecoder().decode(TrafficPackage.self, from: content) {
                allTrafficPackages.append(package)
            }
        case .websocket:
            if let stream = try? JSONDecoder().decode(StreamContent.self, from: content),
               let message = stream.websocketMessagePackage {
                allStreamMessages.append(StreamMessage(url: stream.request.url,
                                                       messageType: message.messageType,
                                                       stringValue: message.stringValue,
                                                       dataValue: message.dataValue))
            }
        case .connection:
            break
        }
    }

    /// Match by the path and the query, the scheme might be changed (e.g. ws -> http)
    func trafficPackages(for url: URL) -> [TrafficPackage] {
        let key = CapturingTransporter.matchingKey(url)
        lock.lock()
        defer { lock.unlock() }
        return allTrafficPackages.filter { $0.request.url.hasSuffix(key) }
    }

    func streamMessages(for url: URL) -> [StreamMessage] {
        let key = CapturingTransporter.matchingKey(url)
        lock.lock()
        defer { lock.unlock() }
        return allStreamMessages.filter { $0.url.hasSuffix(key) }
    }

    private static func matchingKey(_ url: URL) -> String {
        return "\(url.host ?? ""):\(url.port ?? 0)\(url.path)?\(url.query ?? "")"
    }
}

private final class TaskDelegate: NSObject, URLSessionDataDelegate {

    private let lock = NSLock()
    private var data = Data()
    var onComplete: ((Error?) -> Void)?

    var receivedData: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        self.data.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(error)
    }
}

/// Respond to `/mock` without the network
private final class MockURLProtocol: URLProtocol {

    static let path = "/mock"
    static let body = Data("mock-body".utf8)

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.path == path
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/plain"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: MockURLProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
