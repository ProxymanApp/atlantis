//
//  Transporter.swift
//  atlantis-iOS
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

public protocol Transporter {

    func send(package: Package)
}

final class NetServiceTransport: Transporter {

    static let shared = NetServiceTransport()
    
    func send(package: Package) {
        
    }
}
