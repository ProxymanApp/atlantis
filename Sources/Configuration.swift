//
//  Configuration.swift
//  atlantis
//
//  Created by Nghia Tran on 10/23/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

public struct Configuration {

    public let projectName: String
    public let deviceName: String
    let id: String

    public static func `default`() -> Configuration {
        let project = Project.current
        let deviceName = Device.current
        return Configuration(projectName: project.name,
                             deviceName: deviceName.name)
    }

    init(projectName: String, deviceName: String) {
        self.projectName = projectName
        self.deviceName = deviceName
        self.id = "\(Project.current.bundleIdentifier)-\(Device.current.model)" // Use this ID to distinguish the message
    }
}
