//
//  Configuration.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

public struct Configuration {

    public let netServiceType: String
    public let netServiceDomain: String

    static func `default`() -> Configuration {
        return Configuration(netServiceType: "_Proxyman._tcp", netServiceDomain: "")
    }
}
