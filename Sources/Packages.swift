//
//  Packages.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

#if os(OSX)
import AppKit
typealias Image = NSImage
#elseif os(iOS) || targetEnvironment(macCatalyst)  || os(tvOS)
import UIKit
typealias Image = UIImage
#endif

struct ConnectionPackage: Codable, Serializable {

    let device: Device
    let project: Project
    let icon: Data?

    init(config: Configuration) {
        var currentDevice = Device.current
        currentDevice.name = config.deviceName
        var currentProject = Project.current
        currentProject.name = config.projectName
        self.device = currentDevice
        self.project = currentProject
        self.icon = Image.appIcon?.getPNGData()
    }

    func toData() -> Data? {
        do {
            return try JSONEncoder().encode(self)
        } catch let error {
            print(error)
        }
        return nil
    }
}

public final class TrafficPackage: Codable, CustomDebugStringConvertible, Serializable {

    public enum PackageType: String, Codable {
        case http
        case websocket
    }

    // Should not change the variable names
    // since we're using Codable in the main app and Atlantis

    public let id: String
    public let startAt: TimeInterval
    public let request: Request
    public private(set) var response: Response?
    public private(set) var error: CustomError?
    public private(set) var responseBodyData: Data
    public private(set) var endAt: TimeInterval?
    public private(set) var lastData: Data?
    public let packageType: PackageType
    private(set) var websocketMessagePackage: WebsocketMessagePackage?

    // MARK: - Variables

    private var isLargeReponseBody: Bool {
        if responseBodyData.count > NetServiceTransport.MaximumSizePackage {
            return true
        }
        return false
    }

    private var isLargeRequestBody: Bool {
        if let requestBody = request.body, requestBody.count > NetServiceTransport.MaximumSizePackage {
            return true
        }
        return false
    }

    // MARK: - Init

    init(id: String,
         request: Request,
         response: Response? = nil,
         responseBodyData: Data? = nil,
         packageType: PackageType = .http,
         startAt: TimeInterval = Date().timeIntervalSince1970,
         endAt: TimeInterval? = nil) {
        self.id = id
        self.request = request
        self.response = nil
        self.startAt = startAt
        self.endAt = endAt
        self.response = response
        self.responseBodyData = responseBodyData ?? Data()
        self.packageType = packageType
    }

    // MARK: - Builder

    static func buildRequest(sessionTask: URLSessionTask, id: String) -> TrafficPackage? {
        guard let currentRequest = sessionTask.currentRequest,
            let request = Request(currentRequest) else { return nil }

        // Check if it's a websocket
        if let websocketClass = NSClassFromString("__NSURLSessionWebSocketTask"),
           sessionTask.isKind(of: websocketClass) {
            return TrafficPackage(id: id, request: request, packageType: .websocket)
        }

        // Or normal websocket
        return TrafficPackage(id: id, request: request)
    }

    static func buildRequest(request: NSURLRequest, id: String) -> TrafficPackage? {
        guard let request = Request(request as URLRequest) else { return nil }
        return TrafficPackage(id: id, request: request)
    }

    static func buildRequest(urlRequest: URLRequest, urlResponse: URLResponse, bodyData: Data?) -> TrafficPackage? {
        guard let request = Request(urlRequest) else { return nil }
        let response = Response(urlResponse)
        return TrafficPackage(id: UUID().uuidString, request: request, response: response, responseBodyData: bodyData)
    }

    static func buildRequest(urlRequest: URLRequest, error: Error) -> TrafficPackage? {
        guard let request = Request(urlRequest) else { return nil }
        let package = TrafficPackage(id: UUID().uuidString, request: request)
        package.updateDidComplete(error)
        return package
    }

    // MARK: - Internal func

    func updateResponse(_ response: URLResponse) {
        // Construct the Response without body
        self.response = Response(response)
    }
    
    func updateDidComplete(_ error: Error?) {
        endAt = Date().timeIntervalSince1970
        if let error = error {
            self.error = CustomError(error)
        }
    }

    func appendRequestData(_ data: Data) {
        // This func should be called in Upload Tasks
        request.appendBody(data)
    }

    func appendResponseData(_ data: Data) {

        // A dirty solution to prevent this method call twice from Method Swizzler
        // It only occurs if it's a LocalDownloadTask
        // LocalDownloadTask call it delegate, so the swap method is called twiced
        //
        // TODO: Inspired from Flex
        // https://github.com/FLEXTool/FLEX/blob/e89fec4b2d7f081aa74067a86811ca115cde280b/Classes/Network/PonyDebugger/FLEXNetworkObserver.m#L133

        // Skip if the same data (same pointer) is called twice
        if let lastData = lastData, data == lastData {
            return
        }
        lastData = data
        responseBodyData.append(data)
    }

    func toData() -> Data? {
        // Set nil to prevent being encode to JSON
        // It might increase the size of the message
        lastData = nil

        // For some reason, JSONEncoder could not allocate enough RAM to encode a large body
        // It crashes the app if the body might be > 100Mb
        // We decice to skip the body, but send the request/response
        // https://github.com/ProxymanApp/atlantis/issues/57
        if isLargeReponseBody {
            self.responseBodyData = "<Skip Large Body>".data(using: String.Encoding.utf8)!
        }
        if isLargeRequestBody {
            self.request.resetBody()
        }

        // Encode to JSON
        do {
            return try JSONEncoder().encode(self)
        } catch let error {
            print(error)
        }
        return nil
    }

    public var debugDescription: String {
        return "Package: id=\(id), request=\(String(describing: request)), response=\(String(describing: response))"
    }

    func setWebsocketMessagePackage(package: WebsocketMessagePackage) {
        self.websocketMessagePackage = package
    }
}

struct Device: Codable {

    var name: String
    let model: String

    static let current = Device()

    init() {
        #if os(OSX)
        let macName = Host.current().name ?? "Unknown Mac Devices"
        name = macName
        model = "\(macName) \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #elseif os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
        let device = UIDevice.current
        name = device.name
        model = "\(device.name) (\(device.systemName) \(device.systemVersion))"
        #endif
    }
}

struct Project: Codable {

    static let current = Project()

    var name: String
    let bundleIdentifier: String

    init() {
        name = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Untitled"
        bundleIdentifier = Bundle.main.bundleIdentifier ?? "No bundle identifier"
    }
}

public struct Header: Codable {

    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public final class Request: Codable {

    // MARK: - Variables

    public let url: String
    public let method: String
    public let headers: [Header]
    public private(set) var body: Data?

    // MARK: - Init

    public init(url: String, method: String, headers: [Header], body: Data?) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    init?(_ urlRequest: URLRequest?) {
        guard let urlRequest = urlRequest else { return nil }
        url = urlRequest.url?.absoluteString ?? "-"
        method = urlRequest.httpMethod ?? "-"
        headers = urlRequest.allHTTPHeaderFields?.map { Header(key: $0.key, value: $0.value ) } ?? []
        body = urlRequest.httpBody
    }

    func appendBody(_ data: Data) {
        if self.body == nil {
            self.body = Data()
        }
        self.body?.append(data)
    }

    func resetBody() {
        self.body = nil
    }
}

public struct Response: Codable {

    // MARK: - Variables

    public let statusCode: Int
    public let headers: [Header]

    // MARK: - Init

    public init(statusCode: Int, headers: [Header]) {
        self.statusCode = statusCode
        self.headers = headers
    }

    init?(_ response: URLResponse) {
        if let httpResponse = response as? HTTPURLResponse {
            statusCode = httpResponse.statusCode
            headers = httpResponse.allHeaderFields.map { Header(key: $0.key as? String ?? "Unknown Key", value: $0.value as? String ?? "Unknown Value" ) }
        } else {
            statusCode = 200
            headers = [Header(key: "Content-Length", value: "\(response.expectedContentLength)"),
                       Header(key: "Content-Type", value: response.mimeType ?? "plain/text")]
        }
    }
}

public struct CustomError: Codable {

    public let code: Int
    public let message: String

    init(_ error: Error) {
        let nsError = error as NSError
        self.code = nsError.code
        self.message = nsError.localizedDescription
    }

    init(_ error: NSError) {
        self.code = error.code
        self.message = error.localizedDescription
    }
}

public struct WebsocketMessagePackage: Codable, Serializable {

    public enum MessageType: String, Codable {
        case pingPong
        case send
        case receive
        case sendCloseMessage
    }

    public enum Message {
        case data(Data)
        case string(String)

        init?(message: URLSessionWebSocketTask.Message) {
            switch message {
            case .data(let data):
                self = .data(data)
            case .string(let str):
                self = .string(str)
            @unknown default:
                return nil
            }
        }
    }

    private let id: String
    private let createdAt: TimeInterval
    private let messageType: MessageType
    private let stringValue: String?
    private let dataValue: Data?

    init(id: String, message: Message, messageType: MessageType) {
        self.messageType = messageType
        self.id = id
        self.createdAt = Date().timeIntervalSince1970
        switch message {
        case .data(let data):
            self.dataValue = data
            self.stringValue = nil
        case .string(let strValue):
            self.stringValue = strValue
            self.dataValue = nil
        }
    }

    init(id: String, closeCode: Int, reason: Data?) {
        self.messageType = .sendCloseMessage
        self.id = id
        self.createdAt = Date().timeIntervalSince1970
        self.stringValue = "\(closeCode)" // Temporarily store the closeCode by String
        self.dataValue = reason
    }

    func toData() -> Data? {
        // Encode to JSON
        do {
            return try JSONEncoder().encode(self)
        } catch let error {
            print(error)
        }
        return nil
    }
}

extension Image {

    static var appIcon: Image? {
        #if os(OSX)
        if Thread.isMainThread {
            return NSApplication.shared.applicationIconImage
        } else {
            return DispatchQueue.main.sync {
                // Must be called on the Main Thread
                // Otherwise, we get a UI Background Checker warnings
                return NSApplication.shared.applicationIconImage
            }
        }

        #elseif targetEnvironment(macCatalyst)
        guard let iconName = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String else {
            return nil
        }
        return Image(named: iconName)
        #elseif os(iOS) || os(tvOS)
        guard let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
              let lastIcon = iconFiles.last else { return nil }
        return Image(named: lastIcon)
        #endif
    }

    func getPNGData() -> Data? {
        #if os(OSX)
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let newRep = NSBitmapImageRep(cgImage: cgImage)
        // Resize, we don't need 1024px size
        newRep.size = CGSize(width: 64, height: 64)
        return newRep.representation(using: .png, properties: [:])
        #elseif os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
        // It's already by 64px
        return self.pngData()
        #endif
    }
}
