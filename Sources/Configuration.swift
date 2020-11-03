//
//  Configuration.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

struct Configuration {

    static let defaultPort: UInt16 = 10909
    let projectName: String
    let deviceName: String
    let id: String
    let port: UInt16

    static func `default`(port: UInt16 = Configuration.defaultPort) -> Configuration {
        let project = Project.current
        let deviceName = Device.current
        return Configuration(projectName: project.name,
                             deviceName: deviceName.name,
                             port: port)
    }

    private init(projectName: String, deviceName: String, port: UInt16) {
        self.projectName = projectName
        self.deviceName = deviceName
        self.id = "\(Project.current.bundleIdentifier)-\(Device.current.model)" // Use this ID to distinguish the message
        self.port = port
    }
}
