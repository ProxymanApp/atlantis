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

struct PrimaryPackage: Package {

    let id: Int
    let device: Device
    let project: Project

    let request: Request?
    let response: Response?

    private init?(request: Request, dataTask: URLSessionTask) {
        self.id = dataTask.taskIdentifier
        self.device = Device.current
        self.project = Project.current
        self.request = request
        self.response = nil
    }

    // MARK: - Builder

    static func buildRequest(dataTask: URLSessionTask) -> PrimaryPackage? {
        guard let currentRequest = dataTask.currentRequest,
            let request = Request(currentRequest) else { return nil }
        return PrimaryPackage(request: request, dataTask: dataTask)
    }

    func toData() -> Data? {
        return nil
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
