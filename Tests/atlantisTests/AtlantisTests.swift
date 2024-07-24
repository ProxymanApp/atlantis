//
//  AtlantisTests.swift
//  Proxyman
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import XCTest
@testable import Atlantis
import Alamofire

class AtlantisTests: XCTestCase {

    // MARK: Variables

    private var session: URLSession!

    // MARK: Base

    override func setUpWithError() throws {
        try super.setUpWithError()

        session = URLSession(configuration: URLSessionConfiguration.ephemeral)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        session.invalidateAndCancel()
        session = nil

        // clear all
        clearCookies()
        clearCredentials()
    }

    private func clearCookies(for storage: HTTPCookieStorage = .shared) {
        storage.cookies?.forEach { storage.deleteCookie($0) }
    }

    private func clearCredentials(for storage: URLCredentialStorage = .shared) {
        for (protectionSpace, credentials) in storage.allCredentials {
            for (_, credential) in credentials {
                storage.remove(credential, for: protectionSpace)
            }
        }
    }

    func testURLSessionDataTask_GET() {
        Atlantis.setIsRunningOniOSPlayground(true)
        Atlantis.start(hostName: "")

        let expectation = expectation(description: "Should call request")
        let param: [String: Any] = ["name": "Proxyman LLC",
                                    "emoji": "✅",
                                    "sorted[0]": [1, 2, 3],
                                    "obj": ["data": "Proxyman%20LLC"]
        ]
        let headers: HTTPHeaders = ["X-Data": "ABCDEF", "Accept": "application/json"]
        AF.request("https://httpbin.proxyman.app/get",
                   method: HTTPMethod.get,
                   parameters: param,
                   headers: headers).responseJSON { response in
            XCTAssertEqual(200, response.response?.statusCode)

            let packages = Atlantis.shared.getAllPendingPackages()
            XCTAssertEqual(1, packages.count)

            guard let package = packages.first as? TrafficPackage else {
                XCTFail()
                return
            }
            print(package.response)

            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
    }
}
