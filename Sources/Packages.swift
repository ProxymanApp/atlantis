//
//  Packages.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import UIKit

public protocol Package {

    func toData() -> Data?
}

struct PrimaryPackage: Package, CustomDebugStringConvertible {

    let id: Int
    let device: Device
    let project: Project

    let request: Request?
    let response: Response?

    private init?(request: Request, sessionTask: URLSessionTask) {
        self.id = sessionTask.taskIdentifier
        self.device = Device.current
        self.project = Project.current
        self.request = request
        self.response = nil
    }

    // MARK: - Builder

    static func buildRequest(sessionTask: URLSessionTask) -> PrimaryPackage? {
        guard let currentRequest = sessionTask.currentRequest,
            let request = Request(currentRequest) else { return nil }
        return PrimaryPackage(request: request, sessionTask: sessionTask)
    }

    func toData() -> Data? {
        return nil
    }

    var debugDescription: String {
        return "Package: id=\(id), device=\(device), project=\(project), request=\(String(describing: request)), response=\(String(describing: response))"
    }
}

struct Device {

    let name: String
    let mode: String

    static let current = Device()

    init() {
        let device = UIDevice.current
        name = device.name
        mode = "\(device.model) (\(device.systemName) \(device.systemVersion)"
    }
}

struct Project {

    static let current = Project()

    let name: String
    let bundleIdentifier: String

    init() {
        name = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Untitled"
        bundleIdentifier = Bundle.main.bundleIdentifier ?? "No bundle identifier"
    }
}

struct Header {

    let key: String
    let value: String
}

struct Request {

    // MARK: - Variables

    let url: String
    let method: String
    let headers: [Header]?
    let body: Any?

    // MARK: - Init

    init?(_ urlRequest: URLRequest?) {
        guard let urlRequest = urlRequest else { return nil }
        url = urlRequest.url?.absoluteString ?? "-"
        method = urlRequest.httpMethod ?? "-"
        headers = urlRequest.allHTTPHeaderFields?.map { Header(key: $0.key, value: $0.value ) }
        body = urlRequest.httpBody
    }
}

struct Response {

    let statusCode: Int
    let statusPhrase: String
    let httpVersion: String
    let headers: [[String: String]]
    let body: Any?
}
