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

        // skip the info.plist file
        Atlantis.setIsRunningOniOSPlayground(true)
        Atlantis.start(hostName: "")
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()

        session.invalidateAndCancel()
        session = nil
        Atlantis.stop()

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
        let expected = #"""
{
  "args": {
    "emoji": "\u2705",
    "name": "Proxyman LLC"
  },
  "headers": {
    "Accept": "application/json",
    "Accept-Encoding": "gzip, br",
    "Accept-Language": "en-VN;q=1.0",
    "Cdn-Loop": "cloudflare",
    "Cf-Connecting-Ip": "104.28.249.53",
    "Cf-Ipcountry": "VN",
    "Cf-Ray": "8a82aa9fedb20457-HKG",
    "Cf-Visitor": "{\"scheme\":\"https\"}",
    "Connection": "Keep-Alive",
    "Host": "httpbin.proxyman.app",
    "User-Agent": "xctest/15.3 (com.apple.dt.xctest.tool; build:22719; iOS 17.4.0) Alamofire/5.9.1",
    "X-Data": "ABCDEF"
  },
  "origin": "104.28.249.53",
  "url": "https://httpbin.proxyman.app/get?emoji=\u2705&name=Proxyman LLC"
}
"""#



        let expectation = expectation(description: "Should call request")
        let param: [String: Any] = ["name": "Proxyman LLC",
                                    "emoji": "✅"
        ]
        let headers: HTTPHeaders = ["X-Data": "ABCDEF", "Accept": "application/json"]
        AF.request("https://httpbin.proxyman.app/get",
                   method: HTTPMethod.get,
                   parameters: param,
                   headers: headers).responseJSON { response in

            let packages = Atlantis.shared.getAllPendingPackages()
            guard let message = packages.first as? Message,
                  let package = message.package as? TrafficPackage else {
                XCTFail()
                return
            }

            XCTAssertEqual(200, response.response?.statusCode)
            XCTAssertEqual(1, packages.count)
            XCTAssertTrue(HTTPBinCompare.isEqualResponse(from: expected, responseData: package.responseBodyData))

            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 10)
    }
}
