//
//  Packages.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import UIKit

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
        self.icon = UIImage.appIcon?.pngData()
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
    private var responseBodyData = Data()
    
    private init?(id: String, request: Request, sessionTask: URLSessionTask) {
        self.id = id
        self.request = request
        self.response = nil
    }

    // MARK: - Builder

    static func buildRequest(sessionTask: URLSessionTask, id: String) -> TrafficPackage? {
        guard let currentRequest = sessionTask.currentRequest,
            let request = Request(currentRequest) else { return nil }
        return TrafficPackage(id: id, request: request, sessionTask: sessionTask)
    }

    func updateResponse(_ response: URLResponse) {
        // Construct the Response without body
        self.response = Response(response)
    }
    
    func updateError(_ error: Error?) {
        guard let error = error else { return }
        self.error = CustomError(error)
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
        let device = UIDevice.current
        name = device.name
        model = "\(device.name) (\(device.systemName) \(device.systemVersion))"
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

struct Header: Codable {

    let key: String
    let value: String
}

struct Request: Codable {

    // MARK: - Variables

    let url: String
    let method: String
    let headers: [Header]?
    let body: Data?

    // MARK: - Init

    init?(_ urlRequest: URLRequest?) {
        guard let urlRequest = urlRequest else { return nil }
        url = urlRequest.url?.absoluteString ?? "-"
        method = urlRequest.httpMethod ?? "-"
        headers = urlRequest.allHTTPHeaderFields?.map { Header(key: $0.key, value: $0.value ) }
        body = urlRequest.httpBody
    }
}

struct Response: Codable {

    let statusCode: Int
    let headers: [Header]?

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

extension UIImage {
    static var appIcon: UIImage? {
        guard let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String:Any],
              let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String:Any],
              let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
              let lastIcon = iconFiles.last else { return nil }
        return UIImage(named: lastIcon)
    }
}
