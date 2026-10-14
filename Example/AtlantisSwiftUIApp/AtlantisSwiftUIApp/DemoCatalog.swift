//
//  DemoCatalog.swift
//  AtlantisSwiftUIApp
//

import SwiftUI

extension DemoPage {

    var title: String {
        switch self {
        case .iOS18: return "iOS 18"
        case .iOS26: return "iOS 26"
        case .iOS27: return "iOS 27"
        }
    }

    var symbol: String {
        switch self {
        case .iOS18: return "18.circle"
        case .iOS26: return "26.circle"
        case .iOS27: return "27.circle"
        }
    }

    var sections: [DemoSection] {
        switch self {
        case .iOS18:
            // The classic loader, the default one
            return Self.urlSessionSections(page: self, loader: .classic)
        case .iOS26:
            // The new loader (usesClassicLoadingMode = false)
            return [Self.iOS26Section] + Self.urlSessionSections(page: self, loader: .new)
        case .iOS27:
            return Self.iOS27Sections
        }
    }
}

// MARK: - URLSession

private extension DemoPage {

    /// The same APIs for each loader, but Atlantis swizzles different classes
    static func urlSessionSections(page: DemoPage, loader: URLSessionLoader) -> [DemoSection] {
        let isClassic = loader == .classic
        let requirement: Demo.Requirement = isClassic ? .none : .iOS18_4
        let session = isClassic ? "NSURLSession" : "NWURLSession"
        let completionConsumer = isClassic ? "__NSCFURLLocalSessionConnection" : "NWURLSessionResponseConsumerDataCompletionHandler"
        let delegateConsumer = isClassic ? "__NSCFURLLocalSessionConnection" : "NWURLSessionResponseConsumerDataDelegate"
        let downloadConsumer = isClassic ? "__NSCFURLLocalSessionConnection" : "NWURLSessionResponseConsumerDownload"
        let id = { (name: String) in "\(page.rawValue).\(name)" }

        return [
            DemoSection(title: "Data Task", demos: [
                Demo(id: id("get"), title: "GET Request", swizzled: completionConsumer,
                     symbol: "arrow.down.circle", tint: .blue, requirement: requirement,
                     action: .request { try await DemoRequests.get(loader, demo: id("get")) }),
                Demo(id: id("post"), title: "POST Request", swizzled: completionConsumer,
                     symbol: "arrow.up.circle", tint: .blue, requirement: requirement,
                     action: .request { try await DemoRequests.post(loader, demo: id("post")) }),
                Demo(id: id("delegate"), title: "Data Task Delegate", swizzled: delegateConsumer,
                     symbol: "arrow.left.arrow.right", tint: .blue, requirement: requirement,
                     action: .request { try await DemoRequests.dataTaskWithDelegate(loader, demo: id("delegate")) })
            ]),
            DemoSection(title: "Upload & Download", demos: [
                Demo(id: id("uploadData"), title: "Upload Data", swizzled: "-[\(session) uploadTaskWithRequest:fromData:completionHandler:]",
                     symbol: "arrow.up.doc", tint: .orange, requirement: requirement,
                     action: .request { try await DemoRequests.uploadData(loader, demo: id("uploadData")) }),
                Demo(id: id("uploadFile"), title: "Upload File", swizzled: "-[\(session) uploadTaskWithRequest:fromFile:completionHandler:]",
                     symbol: "folder", tint: .orange, requirement: requirement,
                     action: .request { try await DemoRequests.uploadFile(loader, demo: id("uploadFile")) }),
                Demo(id: id("download"), title: "Download", swizzled: downloadConsumer,
                     symbol: "arrow.down.doc", tint: .orange, requirement: requirement,
                     action: .request { try await DemoRequests.downloadTask(loader, demo: id("download")) })
            ]),
            DemoSection(title: "Async/Await", demos: [
                Demo(id: id("asyncData"), title: "data(for:)", swizzled: completionConsumer,
                     symbol: "bolt", tint: .purple, requirement: requirement,
                     action: .request { try await DemoRequests.asyncData(loader, demo: id("asyncData")) }),
                Demo(id: id("asyncBytes"), title: "bytes(for:)", swizzled: delegateConsumer,
                     symbol: "waveform", tint: .purple, requirement: requirement,
                     action: .request { try await DemoRequests.asyncBytes(loader, demo: id("asyncBytes")) }),
                Demo(id: id("asyncUploadData"), title: "upload(for:from:)", swizzled: "-[\(session) _uploadTaskWithRequest:fromData:delegate:completionHandler:]",
                     symbol: "arrow.up.doc", tint: .purple, requirement: requirement,
                     action: .request { try await DemoRequests.asyncUploadData(loader, demo: id("asyncUploadData")) }),
                Demo(id: id("asyncUploadFile"), title: "upload(for:fromFile:)", swizzled: "-[\(session) _uploadTaskWithRequest:fromFile:delegate:completionHandler:]",
                     symbol: "folder", tint: .purple, requirement: requirement,
                     action: .request { try await DemoRequests.asyncUploadFile(loader, demo: id("asyncUploadFile")) }),
                Demo(id: id("asyncDownload"), title: "download(for:)", swizzled: downloadConsumer,
                     symbol: "arrow.down.doc", tint: .purple, requirement: requirement,
                     action: .request { try await DemoRequests.asyncDownload(loader, demo: id("asyncDownload")) })
            ]),
            DemoSection(title: "Streaming", demos: [
                Demo(id: id("sse"), title: "Server-Sent Events", swizzled: delegateConsumer,
                     symbol: "dot.radiowaves.up.forward", tint: .pink, requirement: requirement,
                     action: .request { try await DemoRequests.serverSentEvents(loader, demo: id("sse")) })
            ]),
            webSocketSection(id: id, loader: loader, requirement: requirement)
        ]
    }

    /// URLSessionWebSocketTask: each row calls one API on the same connection
    static func webSocketSection(id: (String) -> String, loader: URLSessionLoader, requirement: Demo.Requirement) -> DemoSection {
        let isClassic = loader == .classic
        let webSocketTask = isClassic ? "__NSURLSessionWebSocketTask" : "NWURLSessionWebSocketTask"
        let handshake = isClassic ? "__NSCFURLLocalSessionConnection" : "-[NWURLSessionTask loaderConnectedWithHTTPConnectionMetadata:CNAMEChain:unlistedTracker:]"
        let webSocket = DemoWebSocket.shared(loader)

        return DemoSection(title: "WebSocket", demos: [
            Demo(id: id("webSocketConnect"), title: "Connect", swizzled: handshake,
                 symbol: "link", tint: .red, requirement: requirement,
                 action: .request { try await webSocket.connect() }),
            Demo(id: id("webSocketSendText"), title: "Send Text", swizzled: "-[\(webSocketTask) sendMessage:completionHandler:]",
                 symbol: "text.bubble", tint: .red, requirement: requirement,
                 action: .webSocket { try await webSocket.sendText() }),
            Demo(id: id("webSocketSendData"), title: "Send Data", swizzled: "-[\(webSocketTask) sendMessage:completionHandler:]",
                 symbol: "01.square", tint: .red, requirement: requirement,
                 action: .webSocket { try await webSocket.sendData() }),
            Demo(id: id("webSocketReceive"), title: "Receive", swizzled: "-[\(webSocketTask) receiveMessageWithCompletionHandler:]",
                 symbol: "arrow.down.message", tint: .red, requirement: requirement,
                 action: .webSocket { try await webSocket.receive() }),
            Demo(id: id("webSocketPing"), title: "Ping", swizzled: "-[\(webSocketTask) sendPingWithPongReceiveHandler:]",
                 symbol: "dot.radiowaves.left.and.right", tint: .red, requirement: requirement,
                 action: .webSocket { try await webSocket.ping() }),
            Demo(id: id("webSocketClose"), title: "Close", swizzled: "-[\(webSocketTask) cancelWithCloseCode:reason:]",
                 symbol: "xmark.circle", tint: .red, requirement: requirement,
                 action: .webSocket { await webSocket.close() })
        ])
    }
}

// MARK: - iOS 26

private extension DemoPage {

    static var iOS26Section: DemoSection {
        let earlyData = "iOS26.earlyData"
        let ultraConstrained = "iOS26.ultraConstrained"
        return DemoSection(title: "New in iOS 26", demos: [
            Demo(id: earlyData, title: "HTTP/3 Early Data", swizzled: "NWURLSessionResponseConsumerDataCompletionHandler",
                 symbol: "hare", tint: .green, requirement: .iOS26,
                 action: .request { try await DemoRequests.earlyData(demo: earlyData) }),
            Demo(id: ultraConstrained, title: "Ultra Constrained Network", swizzled: "NWURLSessionResponseConsumerDataCompletionHandler",
                 symbol: "antenna.radiowaves.left.and.right.circle", tint: .green, requirement: .iOS26_1,
                 action: .request { try await DemoRequests.ultraConstrainedNetwork(demo: ultraConstrained) })
        ])
    }
}

// MARK: - iOS 27

private extension DemoPage {

    static var iOS27Sections: [DemoSection] {
        let classicData = "iOS27.classicData"
        let newData = "iOS27.newData"
        let newWebSocket = "iOS27.newWebSocket"
        return [
            DemoSection(title: "New in iOS 27", demos: [
                Demo(id: "iOS27.asyncImageRequest", title: "AsyncImage(request:)", swizzled: "__NSCFURLLocalSessionConnection",
                     symbol: "photo", tint: .teal, requirement: .iOS27,
                     action: .image(.classic)),
                Demo(id: "iOS27.asyncImageSession", title: "asyncImageURLSession(_:)", swizzled: "NWURLSessionResponseConsumerDataCompletionHandler",
                     symbol: "photo.on.rectangle", tint: .teal, requirement: .iOS27,
                     action: .image(.new))
            ]),
            DemoSection(title: "Both Loaders", demos: [
                Demo(id: classicData, title: "Classic Loader", swizzled: "__NSCFURLLocalSessionConnection",
                     symbol: "bolt", tint: .indigo,
                     action: .request { try await DemoRequests.asyncData(.classic, demo: classicData) }),
                Demo(id: newData, title: "New Loader", swizzled: "NWURLSessionResponseConsumerDataCompletionHandler",
                     symbol: "bolt.fill", tint: .indigo, requirement: .iOS18_4,
                     action: .request { try await DemoRequests.asyncData(.new, demo: newData) }),
                Demo(id: newWebSocket, title: "New Loader WebSocket", swizzled: "NWURLSessionWebSocketTask",
                     symbol: "antenna.radiowaves.left.and.right", tint: .indigo, requirement: .iOS18_4,
                     action: .request { try await DemoRequests.webSocket(.new, demo: newWebSocket) })
            ])
        ]
    }
}
