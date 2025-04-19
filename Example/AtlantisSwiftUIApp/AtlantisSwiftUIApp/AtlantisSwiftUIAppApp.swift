//
//  AtlantisSwiftUIAppApp.swift
//  AtlantisSwiftUIApp
//
//  Created by nghiatran on 23/3/25.
//

import SwiftUI

#if DEBUG
// 1. Import Atlantis
import Atlantis
#endif

@main
struct AtlantisSwiftUIAppApp: App {

    init() {
        // 2. Connect to your Macbook
        #if DEBUG
        Atlantis.start()
        
        // 3. (Optional)
        // If you have many Macbooks on the same WiFi Network, you can specify your Macbook's name
        // Find your Macbook's name by opening Proxyman App -> Certificate Menu -> Install Certificate for iOS -> With Atlantis ->
        // Click on "How to start Atlantis" -> Select "SwiftUI" Tab
        // Atlantis.start("Your's Macbook Pro")
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
