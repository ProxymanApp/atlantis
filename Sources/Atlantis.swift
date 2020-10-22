//
//  Atlantis.swift
//  atlantis
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

/// Inspire from Flex
/// https://github.com/FLEXTool/FLEX/tree/master/Classes/Network/PonyDebugger
final class Atlantis: NSObject {

    private struct Constants {
        static let isEnabledNetworkInjector = "isEnabledNetworkInjector"
    }

    // MARK: - Variables

    static var isEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: Constants.isEnabledNetworkInjector)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Constants.isEnabledNetworkInjector)
            if newValue {
                injectAllNetworkClasses()
            }
        }
    }
}

// MARK: - Injection Methods

extension Atlantis {

    private class func injectAllNetworkClasses() {
        DispatchQueue.once {

        }
    }
}
