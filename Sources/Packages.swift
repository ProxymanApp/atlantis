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
#elseif os(iOS) || targetEnvironment(macCatalyst)
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

final class TrafficPackage: Codable, CustomDebugStringConvertible, Serializable {

    let id: String
    private let request: Request
    private var response: Response?
    private(set) var error: CustomError?
    private var responseBodyData: Data
    private let startAt: TimeInterval
    private var endAt: TimeInterval?

    init(id: String, request: Request, response: Response? = nil, responseBodyData: Data? = nil) {
        self.id = id
        self.request = request
        self.response = nil
        self.startAt = Date().timeIntervalSince1970
        self.response = response
        self.responseBodyData = responseBodyData ?? Data()
    }

    // MARK: - Builder

    static func buildRequest(sessionTask: URLSessionTask, id: String) -> TrafficPackage? {
        guard let currentRequest = sessionTask.currentRequest,
            let request = Request(currentRequest) else { return nil }
        return TrafficPackage(id: id, request: request)
    }

    static func buildRequest(connection: NSURLConnection, id: String) -> TrafficPackage? {
        guard let request = Request(connection.currentRequest) else { return nil }
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

    func append(_ data: Data) {
        responseBodyData.append(data)
    }

    func toData() -> Data? {
        do {
            return try JSONEncoder().encode(self)
        } catch let error {
            print(error)
        }
        return nil
    }

    var debugDescription: String {
        return "Package: id=\(id), request=\(String(describing: request)), response=\(String(describing: response))"
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
        #elseif os(iOS) || targetEnvironment(macCatalyst)
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

    let key: String
    let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct Request: Codable {

    // MARK: - Variables

    let url: String
    let method: String
    let headers: [Header]
    let body: Data?

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
}

public struct Response: Codable {

    // MARK: - Variables

    let statusCode: Int
    let headers: [Header]

    // MARK: - Init

    public init(statusCode: Int, headers: [Header]) {
        self.statusCode = statusCode
        self.headers = headers
    }

    init?(_ response: URLResponse) {
        guard let httpResponse = response as? HTTPURLResponse else {
            assertionFailure("Only support HTTPURLResponse")
            return nil
        }
        statusCode = httpResponse.statusCode
        headers = httpResponse.allHeaderFields.map { Header(key: $0.key as? String ?? "Unknown Key", value: $0.value as? String ?? "Unknown Value" ) }
    }
}

struct CustomError: Codable {

    let code: Int
    let message: String

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

extension Image {

    static var appIcon: Image? {
        #if os(OSX)
        return NSApplication.shared.applicationIconImage
        #elseif targetEnvironment(macCatalyst)
        guard let iconName = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String else {
            return nil
        }
        return Image(named: iconName)
        #elseif os(iOS)
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
        #elseif os(iOS) || targetEnvironment(macCatalyst)
        // It's already by 64px
        return self.pngData()
        #endif
    }
}
