//
//  Atlantis+Manual.swift
//  Atlantis
//
//  Created by Nghia Tran on 11/7/20.
//

import Foundation

extension Atlantis {

    /// Handy func to manually add Request & Response to Atlantis, then sending to Proxyman app for inspecting.
    /// It's useful if your app makes HTTP Request that not using URLSession or NSURLConnection. e.g. Swift-NIO-GRPC, C++ Network library, ...
    /// - Parameters:
    ///   - request: Request that needs send to Proxyman
    ///   - response: Response that needs send to Proxyman
    ///   - responseBody: The body Data of the response
    public class func add(request: URLRequest, response: URLResponse, responseBody: Data? = nil) {
        // Build package from raw given input
        guard let package = TrafficPackage.buildRequest(urlRequest: request, urlResponse: response, bodyData: responseBody) else {
            print("[Atlantis][Error] Could not build TrafficPackage from manual input. Please contact the author!")
            return
        }

        // Compose and send the message to Proxyman
        Atlantis.shared.startSendingMessage(package: package)
    }


    /// Handy func to manually add Request and Response Error to Atlantis, then sending to Proxyman app for inspecting.
    /// - Parameters:
    ///   - request: The Request that needs send to Proxyman
    ///   - error: The error from network, Response ...
    public class func add(request: URLRequest, error: Error) {
        guard let package = TrafficPackage.buildRequest(urlRequest: request, error: error) else {
            print("[Atlantis][Error] Could not build TrafficPackage from manual input. Please contact the author!")
            return
        }

        // Compose and send the message to Proxyman
        Atlantis.shared.startSendingMessage(package: package)
    }
}
