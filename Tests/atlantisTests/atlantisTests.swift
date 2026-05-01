import Foundation
import ObjectiveC
import XCTest
@testable import Atlantis

private struct TestMessageEnvelope: Codable {
    let id: String?
    let messageType: Message.MessageType
    let content: Data?
    let buildVersion: String?
}

private final class TestTransporter: Transporter {
    private let queue = DispatchQueue(label: "com.proxyman.atlantis.tests.transporter")
    private var messages: [TestMessageEnvelope] = []
    var onTrafficPackage: ((TrafficPackage) -> Void)?

    func start(_ config: Configuration) {
        // No-op: avoid Bonjour/network in tests.
    }

    func stop() {
        // No-op
    }

    func send(package: Serializable) {
        guard let data = package.toData(),
              let envelope = try? JSONDecoder().decode(TestMessageEnvelope.self, from: data) else {
            return
        }
        queue.async {
            self.messages.append(envelope)
        }
        guard envelope.messageType == .traffic,
              let content = envelope.content,
              let traffic = try? JSONDecoder().decode(TrafficPackage.self, from: content) else {
            return
        }
        onTrafficPackage?(traffic)
    }

    func drainMessages() -> [TestMessageEnvelope] {
        queue.sync { messages }
    }
}

private enum LocalSSEServerError: Error, CustomStringConvertible {
    case missingResource
    case invalidPort(String)
    case timedOut(String, String)

    var description: String {
        switch self {
        case .missingResource:
            return "Could not find sse-server.js test resource"
        case .invalidPort(let output):
            return "Could not parse SSE server port from stdout: \(output)"
        case .timedOut(let stdout, let stderr):
            return "Timed out waiting for SSE server. stdout: \(stdout), stderr: \(stderr)"
        }
    }
}

private final class LocalSSEServer {
    private let process: Process
    private let stdout: Pipe
    private let stderr: Pipe
    private let port: Int

    private init(process: Process, stdout: Pipe, stderr: Pipe, port: Int) {
        self.process = process
        self.stdout = stdout
        self.stderr = stderr
        self.port = port
    }

    static func start() throws -> LocalSSEServer {
        guard let scriptURL = Bundle.module.url(forResource: "sse-server", withExtension: "js") else {
            throw LocalSSEServerError.missingResource
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let outputQueue = DispatchQueue(label: "com.proxyman.atlantis.tests.sse-server-output")
        let ready = DispatchSemaphore(value: 0)
        var stdoutText = ""
        var stderrText = ""
        var parsedPort: Int?

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", scriptURL.path]
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputQueue.sync {
                stdoutText += text
                if parsedPort == nil, let port = parsePort(from: stdoutText) {
                    parsedPort = port
                    ready.signal()
                }
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            outputQueue.sync {
                stderrText += text
            }
        }

        try process.run()

        guard ready.wait(timeout: .now() + 5) == .success else {
            let output = outputQueue.sync { (stdoutText, stderrText) }
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
            throw LocalSSEServerError.timedOut(output.0, output.1)
        }

        guard let port = outputQueue.sync(execute: { parsedPort }) else {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
            throw LocalSSEServerError.invalidPort(outputQueue.sync { stdoutText })
        }

        return LocalSSEServer(process: process, stdout: stdout, stderr: stderr, port: port)
    }

    func url(path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    func stop() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    deinit {
        stop()
    }
}

private func parsePort(from text: String) -> Int? {
    text.split(whereSeparator: \.isNewline).compactMap { line -> Int? in
        guard line.hasPrefix("PORT ") else { return nil }
        return Int(line.dropFirst("PORT ".count))
    }.first
}

final class URLSessionSwizzleTests: XCTestCase {
    private let baseURL = URL(string: "https://httpbin.proxyman.app")!
    private var transporter: TestTransporter!

    override func setUp() {
        super.setUp()
        transporter = TestTransporter()
        Atlantis.setIsRunningOniOSPlayground(true)
        Atlantis.setEnableTransportLayer(true)
        Atlantis.setTransporterForTesting(transporter)
        Atlantis.start()
    }

    override func tearDown() {
        Atlantis.stop()
        transporter = nil
        super.tearDown()
    }

    func testSelectorExistenceForSwizzledAPIs() {
        let sessionClass = NSClassFromString("__NSCFURLLocalSessionConnection")
            ?? NSClassFromString("__NSCFURLSessionConnection")
        XCTAssertNotNil(sessionClass)
        if let sessionClass = sessionClass {
            let responseSelector: Selector
            if #available(iOS 16.0, tvOS 16.0, *) {
                responseSelector = NSSelectorFromString("_didReceiveResponse:sniff:")
            } else if #available(iOS 13.0, tvOS 13.0, *) {
                responseSelector = NSSelectorFromString("_didReceiveResponse:sniff:rewrite:")
            } else {
                responseSelector = NSSelectorFromString("_didReceiveResponse:sniff:")
            }
            assertSelectorExists(baseClass: sessionClass, selector: responseSelector, name: "URLSession response")
            assertSelectorExists(baseClass: sessionClass, selector: NSSelectorFromString("_didReceiveData:"), name: "URLSession data")
            assertSelectorExists(baseClass: sessionClass, selector: NSSelectorFromString("_didFinishWithError:"), name: "URLSession complete")
        }

        let resumeClass: AnyClass? = {
            if !ProcessInfo.processInfo.responds(to: #selector(getter: ProcessInfo.operatingSystemVersion)) {
                return NSClassFromString("__NSCFLocalSessionTask")
            }
            let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            if majorVersion < 9 || majorVersion >= 14 {
                return URLSessionTask.self
            }
            return NSClassFromString("__NSCFURLSessionTask")
        }()
        XCTAssertNotNil(resumeClass)
        if let resumeClass = resumeClass {
            assertSelectorExists(baseClass: resumeClass, selector: NSSelectorFromString("resume"), name: "URLSession resume")
        }

        let urlSessionClass: AnyClass = URLSession.self
        assertSelectorExists(baseClass: urlSessionClass, selector: NSSelectorFromString("uploadTaskWithRequest:fromFile:"), name: "upload from file")
        assertSelectorExists(baseClass: urlSessionClass, selector: NSSelectorFromString("uploadTaskWithRequest:fromFile:completionHandler:"), name: "upload from file + completion")
        assertSelectorExists(baseClass: urlSessionClass, selector: NSSelectorFromString("uploadTaskWithRequest:fromData:"), name: "upload from data")
        assertSelectorExists(baseClass: urlSessionClass, selector: NSSelectorFromString("uploadTaskWithRequest:fromData:completionHandler:"), name: "upload from data + completion")

        let webSocketClass = NSClassFromString("__NSURLSessionWebSocketTask")
        XCTAssertNotNil(webSocketClass)
        if let webSocketClass = webSocketClass {
            assertSelectorExists(baseClass: webSocketClass, selector: NSSelectorFromString("sendMessage:completionHandler:"), name: "websocket send")
            assertSelectorExists(baseClass: webSocketClass, selector: NSSelectorFromString("receiveMessageWithCompletionHandler:"), name: "websocket receive")
            assertSelectorExists(baseClass: webSocketClass, selector: NSSelectorFromString("sendPingWithPongReceiveHandler:"), name: "websocket ping/pong")
            assertSelectorExists(baseClass: webSocketClass, selector: NSSelectorFromString("cancelWithCloseCode:reason:"), name: "websocket cancel")
        }
    }

    func testGetRequestCaptured() {
        let url = baseURL.appendingPathComponent("get")
        let package = waitForTrafficPackage(matching: { package in
            package.request.method == "GET" && package.request.url.contains("/get")
        }) {
            let session = makeSession()
            let task = session.dataTask(with: url)
            task.resume()
        }
        assertPackageHasSuccessResponse(package)
        XCTAssertEqual(package.request.method, "GET")
        XCTAssertTrue(package.request.url.contains("/get"))
        XCTAssertFalse(package.responseBodyData.isEmpty)
    }

    func testPostRequestCaptured() {
        let url = baseURL.appendingPathComponent("post")
        let body = "hello-atlantis".data(using: .utf8)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let package = waitForTrafficPackage(matching: { package in
            package.request.method == "POST" && package.request.url.contains("/post")
        }) {
            let session = makeSession()
            let task = session.dataTask(with: request)
            task.resume()
        }
        assertPackageHasSuccessResponse(package)
        XCTAssertEqual(package.request.body, body)
        XCTAssertFalse(package.responseBodyData.isEmpty)
    }

    func testDownloadRequestCaptured() {
        let url = baseURL.appendingPathComponent("bytes/32")
        let package = waitForTrafficPackage(matching: { package in
            package.request.method == "GET" && package.request.url.contains("/bytes/32")
        }) {
            let session = makeSession()
            let task = session.downloadTask(with: url)
            task.resume()
        }
        assertPackageHasSuccessResponse(package)
        XCTAssertFalse(package.responseBodyData.isEmpty)
    }

    func testUploadFromDataCaptured() {
        let url = baseURL.appendingPathComponent("post")
        let body = "upload-data-body".data(using: .utf8)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let package = waitForTrafficPackage(matching: { package in
            package.request.method == "POST" && package.request.url.contains("/post")
        }) {
            let session = makeSession()
            let task = session.uploadTask(with: request, from: body)
            task.resume()
        }
        assertPackageHasSuccessResponse(package)
        XCTAssertEqual(package.request.body, body)
    }

    func testUploadFromDataWithCompletionCaptured() {
        let url = baseURL.appendingPathComponent("post")
        let body = "upload-data-body-completion".data(using: .utf8)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let package = waitForTrafficPackage(matching: { package in
            package.request.method == "POST" && package.request.url.contains("/post")
        }) {
            let session = makeSession()
            let task = session.uploadTask(with: request, from: body) { _, _, _ in }
            task.resume()
        }
        assertPackageHasSuccessResponse(package)
        XCTAssertEqual(package.request.body, body)
    }

    func testUploadFromFileCaptured() {
        let url = baseURL.appendingPathComponent("post")
        let body = "upload-file-body".data(using: .utf8)!
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? body.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let package = waitForTrafficPackage(matching: { package in
            package.request.method == "POST" && package.request.url.contains("/post")
        }) {
            let session = makeSession()
            let task = session.uploadTask(with: request, fromFile: fileURL)
            task.resume()
        }
        assertPackageHasSuccessResponse(package)
        XCTAssertEqual(package.request.body, body)
    }

    func testUploadFromFileWithCompletionCaptured() {
        let url = baseURL.appendingPathComponent("post")
        let body = "upload-file-body-completion".data(using: .utf8)!
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? body.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let package = waitForTrafficPackage(matching: { package in
            package.request.method == "POST" && package.request.url.contains("/post")
        }) {
            let session = makeSession()
            let task = session.uploadTask(with: request, fromFile: fileURL) { _, _, _ in }
            task.resume()
        }
        assertPackageHasSuccessResponse(package)
        XCTAssertEqual(package.request.body, body)
    }

    func testServerSentEventsBasicStreamCapturedBeforeCompletion() throws {
        let server = try LocalSSEServer.start()
        defer { server.stop() }

        var session: URLSession?
        var task: URLSessionDataTask?
        defer {
            task?.cancel()
            session?.invalidateAndCancel()
        }

        let package = waitForTrafficPackageIfAvailable(matching: { package in
            self.isPackageForPath(package, "/basic") &&
            package.endAt == nil &&
            self.responseBodyString(package).contains("data: goodbye-atlantis")
        }, timeout: 10) {
            session = makeSession()
            var request = URLRequest(url: server.url(path: "/basic"))
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            task = session?.dataTask(with: request)
            task?.resume()
        }

        guard let package else {
            XCTFail("Atlantis did not emit an SSE package before the stream completed")
            return
        }

        assertServerSentEventPackage(package)
        let body = responseBodyString(package)
        XCTAssertTrue(body.contains("event: greeting"))
        XCTAssertTrue(body.contains("id: basic-1"))
        XCTAssertTrue(body.contains("data: hello-atlantis"))
        XCTAssertTrue(body.contains("id: basic-2"))
        XCTAssertTrue(body.contains("data: goodbye-atlantis"))
    }

    func testServerSentEventsMultilineEventCapturedBeforeCompletion() throws {
        let server = try LocalSSEServer.start()
        defer { server.stop() }

        var session: URLSession?
        var task: URLSessionDataTask?
        defer {
            task?.cancel()
            session?.invalidateAndCancel()
        }

        let package = waitForTrafficPackageIfAvailable(matching: { package in
            self.isPackageForPath(package, "/multiline") &&
            package.endAt == nil &&
            self.responseBodyString(package).contains("data: second line")
        }, timeout: 10) {
            session = makeSession()
            var request = URLRequest(url: server.url(path: "/multiline"))
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            task = session?.dataTask(with: request)
            task?.resume()
        }

        guard let package else {
            XCTFail("Atlantis did not emit a multiline SSE package before the stream completed")
            return
        }

        assertServerSentEventPackage(package)
        let body = responseBodyString(package)
        XCTAssertTrue(body.contains("event: note"))
        XCTAssertTrue(body.contains("id: multiline-1"))
        XCTAssertTrue(body.contains("data: first line"))
        XCTAssertTrue(body.contains("data: second line"))
    }

    func testServerSentEventsCommentAndRetryCapturedBeforeCompletion() throws {
        let server = try LocalSSEServer.start()
        defer { server.stop() }

        var session: URLSession?
        var task: URLSessionDataTask?
        defer {
            task?.cancel()
            session?.invalidateAndCancel()
        }

        let package = waitForTrafficPackageIfAvailable(matching: { package in
            self.isPackageForPath(package, "/comment-retry") &&
            package.endAt == nil &&
            self.responseBodyString(package).contains("data: after-comment")
        }, timeout: 10) {
            session = makeSession()
            var request = URLRequest(url: server.url(path: "/comment-retry"))
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            task = session?.dataTask(with: request)
            task?.resume()
        }

        guard let package else {
            XCTFail("Atlantis did not emit a comment/retry SSE package before the stream completed")
            return
        }

        assertServerSentEventPackage(package)
        let body = responseBodyString(package)
        XCTAssertTrue(body.contains(": keep-alive"))
        XCTAssertTrue(body.contains("retry: 1500"))
        XCTAssertTrue(body.contains("event: update"))
        XCTAssertTrue(body.contains("data: after-comment"))
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }

    private func waitForTrafficPackageIfAvailable(matching predicate: @escaping (TrafficPackage) -> Bool,
                                                  timeout: TimeInterval,
                                                  action: () -> Void) -> TrafficPackage? {
        let expectation = expectation(description: "Wait for traffic package")
        let lock = NSLock()
        var capturedPackage: TrafficPackage?
        var didFulfill = false

        transporter.onTrafficPackage = { package in
            guard predicate(package) else { return }
            lock.lock()
            defer { lock.unlock() }
            guard !didFulfill else { return }
            didFulfill = true
            capturedPackage = package
            expectation.fulfill()
        }

        action()
        wait(for: [expectation], timeout: timeout)
        return capturedPackage
    }

    private func waitForTrafficPackage(matching predicate: @escaping (TrafficPackage) -> Bool,
                                       action: () -> Void) -> TrafficPackage {
        let expectation = expectation(description: "Wait for traffic package")
        var capturedPackage: TrafficPackage?
        transporter.onTrafficPackage = { package in
            guard predicate(package) else { return }
            capturedPackage = package
            expectation.fulfill()
        }
        action()
        wait(for: [expectation], timeout: 30)
        return capturedPackage!
    }

    private func assertPackageHasSuccessResponse(_ package: TrafficPackage,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) {
        XCTAssertEqual(package.response?.statusCode, 200, file: file, line: line)
    }

    private func assertServerSentEventPackage(_ package: TrafficPackage,
                                              file: StaticString = #filePath,
                                              line: UInt = #line) {
        XCTAssertEqual(package.response?.statusCode, 200, file: file, line: line)
        XCTAssertNil(package.endAt, "SSE package should be emitted while the stream is still open", file: file, line: line)
        XCTAssertTrue(package.response?.headers.contains { header in
            header.key.caseInsensitiveCompare("Content-Type") == .orderedSame &&
            header.value.range(of: "text/event-stream", options: .caseInsensitive) != nil
        } == true, "Expected text/event-stream response", file: file, line: line)
    }

    private func responseBodyString(_ package: TrafficPackage) -> String {
        String(data: package.responseBodyData, encoding: .utf8) ?? ""
    }

    private func isPackageForPath(_ package: TrafficPackage, _ path: String) -> Bool {
        package.request.method == "GET" && package.request.url.contains(path)
    }

    private func assertSelectorExists(baseClass: AnyClass,
                                      selector: Selector,
                                      name: String,
                                      file: StaticString = #filePath,
                                      line: UInt = #line) {
        let method = class_getInstanceMethod(baseClass, selector)
        XCTAssertNotNil(method, "Missing selector: \(name)", file: file, line: line)
        XCTAssertTrue(baseClass.instancesRespond(to: selector), "Selector not implemented: \(name)", file: file, line: line)
    }
}
