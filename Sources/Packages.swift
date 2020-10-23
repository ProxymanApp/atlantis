//
//  Packages.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

public protocol Package {

    func toData() -> Data?
}

struct Header {

    let key: String
    let value: String
}

struct RequestPackage: Package {

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

    // MARK: - Package

    func toData() -> Data? {
        return nil
    }
}

struct ResponsePackage: Package {

    let statusCode: Int
    let statusPhrase: String
    let httpVersion: String
    let headers: [[String: String]]
    let body: Any?

    func toData() -> Data? {
        return nil
    }
}
