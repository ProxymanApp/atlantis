//
//  Atlantis+Utils.swift
//  atlantis
//
//  Created by Nghia Tran on 10/22/20.
//  Copyright © 2020 Proxyman. All rights reserved.
//

import Foundation

extension Atlantis {

    class func swizzleSelector(for originalSelector: Selector) -> Selector {
        return NSSelectorFromString("_atlantis_swizzle_\(NSStringFromSelector(originalSelector))")
    }
}
