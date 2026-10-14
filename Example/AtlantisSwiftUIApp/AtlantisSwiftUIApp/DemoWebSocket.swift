//
//  DemoWebSocket.swift
//  AtlantisSwiftUIApp
//

import Foundation

/// A WebSocket connection to echo.websocket.org, with URLSessionWebSocketTask.
/// Each row of the WebSocket section calls one API on it. Send, Receive and Ping connect if needed.
/// Like an app, it keeps receiving: URLSession reads a pong only after the messages before it
actor DemoWebSocket {

    typealias Message = URLSessionWebSocketTask.Message

    /// One connection per tab: iOS 18 (classic loader) and iOS 26 (new loader)
    static let classic = DemoWebSocket(loader: .classic, demo: "iOS18.webSocketConnect")
    static let new = DemoWebSocket(loader: .new, demo: "iOS26.webSocketConnect")

    static func shared(_ loader: URLSessionLoader) -> DemoWebSocket {
        return loader == .classic ? classic : new
    }

    private let loader: URLSessionLoader
    /// The handshake is reported with the Connect row
    private let demo: String
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var connecting: Task<URLSessionWebSocketTask, Error>?
    /// What the receive loop got, and the Receive row didn't take yet
    private var inbox: [Message] = []
    /// The Receive row, waiting for the next message
    private var waiter: CheckedContinuation<Message, Error>?

    private init(loader: URLSessionLoader, demo: String) {
        self.loader = loader
        self.demo = demo
    }

    /// A new webSocketTask(with:), resume(), then wait for the handshake
    func connect() async throws -> Int {
        disconnect()
        let task = try await connectedTask()
        return (task.response as? HTTPURLResponse)?.statusCode ?? 101
    }

    func sendText() async throws -> String {
        try await connectedTask().send(.string("Hello from Atlantis (\(loader.rawValue) loader)"))
        return "Sent"
    }

    func sendData() async throws -> String {
        try await connectedTask().send(.data(Data("Binary message from Atlantis".utf8)))
        return "Sent"
    }

    /// The next message from the receive loop: the hello from the server, or an echo
    func receive() async throws -> String {
        _ = try await connectedTask()
        let message = inbox.isEmpty ? try await nextMessage() : inbox.removeFirst()
        switch message {
        case .string:
            return "Text"
        case .data:
            return "Data"
        @unknown default:
            return "OK"
        }
    }

    func ping() async throws -> String {
        let task = try await connectedTask()
        try await Self.withTimeout(10) { done in
            task.sendPing { error in
                done(error.map { .failure($0) } ?? .success(()))
            }
        }
        return "Pong"
    }

    func close() -> String {
        disconnect()
        return "Closed"
    }

    // MARK: - Private

    private func connectedTask() async throws -> URLSessionWebSocketTask {
        if let task = task, task.state == .running {
            return task
        }
        // Several rows might need it at the same time
        if let connecting = connecting {
            return try await connecting.value
        }
        let connecting = Task { try await open() }
        self.connecting = connecting
        defer { self.connecting = nil }
        return try await connecting.value
    }

    private func open() async throws -> URLSessionWebSocketTask {
        disconnect()
        let delegate = DemoWebSocketDelegate()
        let session = DemoRequests.makeSession(loader, delegate: delegate)
        let task = session.webSocketTask(with: DemoRequests.webSocketURL(demo: demo))
        task.resume()
        do {
            try await Self.withTimeout(15) { done in
                delegate.onOpen(done)
            }
        } catch {
            task.cancel()
            session.invalidateAndCancel()
            throw error
        }
        self.session = session
        self.task = task
        Task { await receiveLoop(task) }
        return task
    }

    /// receive() until the connection closes
    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while true {
            do {
                let message = try await task.receive()
                guard task === self.task else { return }
                if let waiter = waiter {
                    self.waiter = nil
                    waiter.resume(returning: message)
                } else {
                    inbox.append(message)
                }
            } catch {
                if task === self.task {
                    resumeWaiter(throwing: error)
                }
                return
            }
        }
    }

    /// Wait for the receive loop, for 10 seconds at most
    private func nextMessage() async throws -> Message {
        let timeout = Task {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            timeOutWaiter()
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
        }
    }

    private func timeOutWaiter() {
        // The message came first
        guard !Task.isCancelled else { return }
        resumeWaiter(throwing: URLError(.timedOut))
    }

    private func resumeWaiter(throwing error: Error) {
        waiter?.resume(throwing: error)
        waiter = nil
    }

    private func disconnect() {
        task?.cancel(with: .normalClosure, reason: Data("Bye".utf8))
        session?.finishTasksAndInvalidate()
        task = nil
        session = nil
        inbox.removeAll()
        resumeWaiter(throwing: URLError(.cancelled))
    }

    /// Wait for the callback, for `seconds` at most
    private static func withTimeout<T>(_ seconds: Double,
                                       _ start: (@escaping @Sendable (Result<T, Error>) -> Void) -> Void) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            let oneShot = OneShot(continuation)
            start { oneShot.resume(with: $0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                oneShot.resume(with: .failure(URLError(.timedOut)))
            }
        }
    }
}

/// Resume a continuation once: with the callback, or with the timeout
private final class OneShot<T>: @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

/// Tell when the handshake is done or failed
private final class DemoWebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {

    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var callback: (@Sendable (Result<Void, Error>) -> Void)?

    func onOpen(_ callback: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.lock()
        if let result = result {
            lock.unlock()
            callback(result)
            return
        }
        self.callback = callback
        lock.unlock()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        finish(.success(()))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(.failure(error ?? URLError(.networkConnectionLost)))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let callback = self.callback
        self.callback = nil
        lock.unlock()
        callback?(result)
    }
}
