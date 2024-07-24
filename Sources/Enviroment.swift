//
//  Enviroment.swift
//
//
//  Created by nghiatran on 24/7/24.
//

import Foundation

struct Enviroment {
    static func isTestingEnv() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UNIT_TEST"] == "1" {
            return true
        }
        return false
        #else
        // In production mode, it must be return false
        return false
        #endif
    }
}
