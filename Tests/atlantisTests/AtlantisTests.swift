//
//  AtlantisTests.swift
//  Proxyman
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation
import XCTest
import Atlantis

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

    func testURLSessionDataTask() {


    }
}
