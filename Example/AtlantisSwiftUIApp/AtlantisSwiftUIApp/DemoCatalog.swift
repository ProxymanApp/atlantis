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

    var tint: Color {
        switch self {
        case .iOS18: return .blue
        case .iOS26: return .indigo
        case .iOS27: return .pink
        }
    }

    var headline: String {
        switch self {
        case .iOS18: return "Classic Loader"
        case .iOS26: return "New Loader"
        case .iOS27: return "AsyncImage and URLSession"
        }
    }

    var message: String {
        switch self {
        case .iOS18:
            return "URLSession's default loader on every OS. Tap an API to send a request, then see it on Proxyman."
        case .iOS26:
            return "URLSession's loader built on Network framework, when usesClassicLoadingMode is false (iOS 18.4+). Early Data on iOS 26 requires it."
        case .iOS27:
            return "iOS 27 doesn't add URLSession APIs. SwiftUI's AsyncImage can load a URLRequest with your URLSession."
        }
    }

    var sections: [DemoSection] {
        switch self {
        case .iOS18:
            return Self.urlSessionSections(page: self, loader: .classic)
        case .iOS26:
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
        let streamConsumer = isClassic ? "-[__NSCFURLLocalSessionConnection _didReceiveData:]" : "NWURLSessionResponseConsumerDataDelegate"
        let webSocketTask = isClassic ? "__NSURLSessionWebSocketTask" : "NWURLSessionWebSocketTask"
        let id = { (name: String) in "\(page.rawValue).\(name)" }

        return [
            DemoSection(
                title: "Data Task",
                footer: isClassic
                    ? "Atlantis swizzles -[NSURLSessionTask resume] and __NSCFURLLocalSessionConnection: _didReceiveResponse:sniff:, _didReceiveData: and _didFinishWithError:."
                    : "NWURLSessionTask doesn't inherit from NSURLSessionTask. Atlantis swizzles -[NWURLSessionTask resume] and the response consumers: task:deliverResponse:completionHandler: and task:deliverData:complete:error:completionHandler:.",
                demos: [
                    Demo(id: id("get"), title: "GET Request", api: "dataTask(with:completionHandler:)",
                         swizzled: completionConsumer, symbol: "arrow.down.circle", tint: .blue, requirement: requirement,
                         action: .request { try await DemoRequests.get(loader, demo: id("get")) }),
                    Demo(id: id("post"), title: "POST JSON Body", api: "dataTask(with:completionHandler:)",
                         swizzled: completionConsumer, symbol: "arrow.up.circle", tint: .blue, requirement: requirement,
                         action: .request { try await DemoRequests.postJSON(loader, demo: id("post")) }),
                    Demo(id: id("delegate"), title: "Data Task with Delegate", api: "dataTask(with:) + URLSessionDataDelegate",
                         swizzled: delegateConsumer, symbol: "arrow.left.arrow.right", tint: .blue, requirement: requirement,
                         action: .request { try await DemoRequests.dataTaskWithDelegate(loader, demo: id("delegate")) })
                ]),
            DemoSection(
                title: "Upload & Download",
                footer: isClassic
                    ? "Atlantis gets the body of an upload from the upload methods of NSURLSession."
                    : "The public upload methods of NWURLSession call the private ones, Atlantis records the body once.",
                demos: [
                    Demo(id: id("uploadData"), title: "Upload Data", api: "uploadTask(with:from:completionHandler:)",
                         swizzled: "-[\(session) uploadTaskWithRequest:fromData:completionHandler:]", symbol: "arrow.up.doc", tint: .orange, requirement: requirement,
                         action: .request { try await DemoRequests.uploadData(loader, demo: id("uploadData")) }),
                    Demo(id: id("uploadFile"), title: "Upload File", api: "uploadTask(with:fromFile:completionHandler:)",
                         swizzled: "-[\(session) uploadTaskWithRequest:fromFile:completionHandler:]", symbol: "folder", tint: .orange, requirement: requirement,
                         action: .request { try await DemoRequests.uploadFile(loader, demo: id("uploadFile")) }),
                    Demo(id: id("download"), title: "Download", api: "downloadTask(with:completionHandler:)",
                         swizzled: downloadConsumer, symbol: "arrow.down.doc", tint: .orange, requirement: requirement,
                         action: .request { try await DemoRequests.downloadTask(loader, demo: id("download")) })
                ]),
            DemoSection(
                title: "Async/Await",
                footer: "upload(for:from:) and upload(for:fromFile:) don't call the public upload methods, Atlantis swizzles the private ones.",
                demos: [
                    Demo(id: id("asyncData"), title: "Async Data", api: "data(for:)",
                         swizzled: completionConsumer, symbol: "bolt", tint: .purple, requirement: requirement,
                         action: .request { try await DemoRequests.asyncData(loader, demo: id("asyncData")) }),
                    Demo(id: id("asyncBytes"), title: "Async Bytes", api: "bytes(for:)",
                         swizzled: streamConsumer, symbol: "waveform", tint: .purple, requirement: requirement,
                         action: .request { try await DemoRequests.asyncBytes(loader, demo: id("asyncBytes")) }),
                    Demo(id: id("asyncUploadData"), title: "Async Upload Data", api: "upload(for:from:)",
                         swizzled: "-[\(session) _uploadTaskWithRequest:fromData:delegate:completionHandler:]", symbol: "arrow.up.doc", tint: .purple, requirement: requirement,
                         action: .request { try await DemoRequests.asyncUploadData(loader, demo: id("asyncUploadData")) }),
                    Demo(id: id("asyncUploadFile"), title: "Async Upload File", api: "upload(for:fromFile:)",
                         swizzled: "-[\(session) _uploadTaskWithRequest:fromFile:delegate:completionHandler:]", symbol: "folder", tint: .purple, requirement: requirement,
                         action: .request { try await DemoRequests.asyncUploadFile(loader, demo: id("asyncUploadFile")) }),
                    Demo(id: id("asyncDownload"), title: "Async Download", api: "download(for:)",
                         swizzled: downloadConsumer, symbol: "arrow.down.doc", tint: .purple, requirement: requirement,
                         action: .request { try await DemoRequests.asyncDownload(loader, demo: id("asyncDownload")) })
                ]),
            DemoSection(
                title: "Streaming",
                footer: isClassic
                    ? "WebSocket: sendMessage:completionHandler:, receiveMessageWithCompletionHandler:, sendPingWithPongReceiveHandler: and cancelWithCloseCode:reason:."
                    : "WebSocket: the same methods on NWURLSessionWebSocketTask. The handshake comes from -[NWURLSessionTask loaderConnectedWithHTTPConnectionMetadata:CNAMEChain:unlistedTracker:].",
                demos: [
                    Demo(id: id("sse"), title: "Server-Sent Events", api: "text/event-stream",
                         swizzled: streamConsumer, symbol: "dot.radiowaves.up.forward", tint: .pink, requirement: requirement,
                         action: .request { try await DemoRequests.serverSentEvents(loader, demo: id("sse")) }),
                    Demo(id: id("webSocket"), title: "WebSocket", api: "webSocketTask(with:)",
                         swizzled: webSocketTask, symbol: "antenna.radiowaves.left.and.right", tint: .pink, requirement: requirement,
                         action: .request { try await DemoRequests.webSocket(loader, demo: id("webSocket")) })
                ])
        ]
    }
}

// MARK: - iOS 26

private extension DemoPage {

    static var iOS26Section: DemoSection {
        let earlyData = "iOS26.earlyData"
        let ultraConstrained = "iOS26.ultraConstrained"
        return DemoSection(
            title: "New in iOS 26",
            footer: "Both use the new loader. Early Data doesn't work with the classic loader.",
            demos: [
                Demo(id: earlyData, title: "HTTP/3 Early Data", api: "enablesEarlyData = true",
                     swizzled: "NWURLSessionResponseConsumerDataCompletionHandler", symbol: "hare", tint: .green, requirement: .iOS26,
                     action: .request { try await DemoRequests.earlyData(demo: earlyData) }),
                Demo(id: ultraConstrained, title: "Ultra Constrained Network", api: "allowsUltraConstrainedNetworkAccess = true",
                     swizzled: "NWURLSessionResponseConsumerDataCompletionHandler", symbol: "antenna.radiowaves.left.and.right.circle", tint: .green, requirement: .iOS26_1,
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
            DemoSection(
                title: "New in iOS 27",
                footer: "AsyncImage loads the image with URLSession, Atlantis captures it from the loader of the session.",
                demos: [
                    Demo(id: "iOS27.asyncImageRequest", title: "Image with URLRequest", api: "AsyncImage(request:)",
                         swizzled: "__NSCFURLLocalSessionConnection", symbol: "photo", tint: .teal, requirement: .iOS27,
                         action: .image(path: "image/png", loader: .classic)),
                    Demo(id: "iOS27.asyncImageSession", title: "Image with URLSession", api: ".asyncImageURLSession(_:)",
                         swizzled: "NWURLSessionResponseConsumerDataCompletionHandler", symbol: "photo.on.rectangle", tint: .teal, requirement: .iOS27,
                         action: .image(path: "image/jpeg", loader: .new))
                ]),
            DemoSection(
                title: "URLSession on iOS 27",
                footer: "No new URLSession APIs. Run them on iOS 27 to check that the swizzled methods still work.",
                demos: [
                    Demo(id: classicData, title: "Classic Loader", api: "data(for:)",
                         swizzled: "__NSCFURLLocalSessionConnection", symbol: "bolt", tint: .indigo,
                         action: .request { try await DemoRequests.asyncData(.classic, demo: classicData) }),
                    Demo(id: newData, title: "New Loader", api: "data(for:)",
                         swizzled: "NWURLSessionResponseConsumerDataCompletionHandler", symbol: "bolt.fill", tint: .indigo, requirement: .iOS18_4,
                         action: .request { try await DemoRequests.asyncData(.new, demo: newData) }),
                    Demo(id: newWebSocket, title: "New Loader WebSocket", api: "webSocketTask(with:)",
                         swizzled: "NWURLSessionWebSocketTask", symbol: "antenna.radiowaves.left.and.right", tint: .indigo, requirement: .iOS18_4,
                         action: .request { try await DemoRequests.webSocket(.new, demo: newWebSocket) })
                ])
        ]
    }
}
