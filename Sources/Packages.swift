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

    var id: String { get }

    func updateResponse(_ response: URLResponse)
    func updateError(_ error: Error?)
    func append(_ data: Data)
    func toData() -> Data?
}

final class PrimaryPackage: Package, Codable, CustomDebugStringConvertible {

    let id: String
    private let device: Device
    private let project: Project

    private let request: Request?
    private let response: Response?
    private(set) var error: CustomError?
    private lazy var accumulateData: Data = Data()
    
    private init?(id: String, request: Request, sessionTask: URLSessionTask) {
        self.id = id
        self.device = Device.current
        self.project = Project.current
        self.request = request
        self.response = nil
    }

    // MARK: - Builder

    static func buildRequest(sessionTask: URLSessionTask, id: String) -> PrimaryPackage? {
        guard let currentRequest = sessionTask.currentRequest,
            let request = Request(currentRequest) else { return nil }
        return PrimaryPackage(id: id, request: request, sessionTask: sessionTask)
    }

    func updateResponse(_ response: URLResponse) {

    }
    
    func updateError(_ error: Error?) {
        guard let error = error else { return }
        self.error = CustomError(error)
    }

    func append(_ data: Data) {
        accumulateData.append(data)
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
        return "Package: id=\(id), device=\(device), project=\(project), request=\(String(describing: request)), response=\(String(describing: response))"
    }
}

struct Device: Codable {

    let name: String
    let mode: String

    static let current = Device()

    init() {
        let device = UIDevice.current
        name = device.name
        mode = "\(device.model) (\(device.systemName) \(device.systemVersion)"
    }
}

struct Project: Codable {

    static let current = Project()

    let name: String
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
    let statusPhrase: String
    let httpVersion: String
    let headers: [Header]?
    let body: Data?
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
