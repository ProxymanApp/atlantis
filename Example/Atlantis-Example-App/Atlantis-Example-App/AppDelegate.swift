//
//  AppDelegate.swift
//  Atlantis-Example-App
//
//  Created by Nghia Tran on 23/10/2021.
//

import UIKit
import Atlantis

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Auto connect to a current Macbook
//        Atlantis.start()
        Atlantis.start()
        
        //
        // If you have multiple Macbook on the same network, let use the following method:
        // You can get the _your_host_name from Proxyman -> Certificate menu -> Install for iOS -> Atlantis -> How to Start Atlantis -> and copy the HostName
        //

        // Atlantis.start(hostName: "_your_host_name")

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

