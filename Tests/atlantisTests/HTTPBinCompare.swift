//
//  HTTPBinCompare.swift
//
//
//  Created by nghiatran on 24/7/24.
//

import Foundation

struct HTTPBinCompare {

    static func isEqualResponse(from expectedJSON: String, responseData: Data) -> Bool {
        guard let from = try? JSONSerialization.jsonObject(with: expectedJSON.data(using: .utf8)!, options: []) else {
            print("❌ Invalid HTTP Bin JSON: \(expectedJSON)")
            return false
        }
        guard let to = try? JSONSerialization.jsonObject(with: responseData, options: []) else {
            print("❌ Invalid HTTP Bin JSON: \(String(data: responseData, encoding: .utf8)!)")
            return false
        }
        return isEqualResponse(from: from, toObj: to)
    }

    static func isEqualResponse(from fromObj: Any, toObj: Any) -> Bool {
        guard let fromDict = fromObj as? [String: Any],
            let toDict = toObj as? [String: Any] else { return false }

        // Args
        guard let fromArg = fromDict["args"] as? [String: String],
              let toArg = toDict["args"] as? [String: String] else {
            return false
        }

        // Urls
        guard let fromURL = fromDict["url"] as? String, let toURL = toDict["url"] as? String else {
            return false
        }

        // Form
        let fromForm = fromDict["form"] as? [String: String] ?? [:]
        let toForm = toDict["form"] as? [String: String] ?? [:]

        // Headers
        guard var fromHeaders = fromDict["headers"] as? [String: String],
                var toHeaders = toDict["headers"] as? [String: String] else {
            return false
        }

        // These headers is changed everytime we run the test
        // It's better to remove them
        let removeHeaders = ["Accept-Encoding",
                             "Accept-Language",
                             "User-Agent",
                             "X-Amzn-Trace-Id",
                             "Cookie",
                             "Transfer-Encoding",
                             "Cdn-Loop",
                             "if-none-match",
                             "Cf-Connecting-Ip", "Cf-Ipcountry", "Cf-Ray", "Cf-Visitor",
                             "X-Proxyman-Uuid",
                             "Connection"]
        for header in removeHeaders {
            fromHeaders.removeValue(forKey: header)
            toHeaders.removeValue(forKey: header)
            fromHeaders.removeValue(forKey: header.lowercased())
            toHeaders.removeValue(forKey: header.lowercased())
        }

        let matched = fromArg == toArg && fromURL == toURL && fromForm == toForm && NSDictionary(dictionary: fromHeaders).isEqual(to: toHeaders)

        // Debug
        if !matched {
            if fromArg != toArg {
                print("------ Unmatched from Arg: ")
                print(fromArg)
                print("------ Unmatched to Arg: ")
                print(toArg)
            }

            if fromURL != toURL {
                print("------ Unmatched from URL: ")
                print(fromURL)
                print("------ Unmatched to URL: ")
                print(toURL)
            }

            if fromForm != toForm {
                print("------ Unmatched from Form: ")
                print(fromForm)
                print("------ Unmatched to Form: ")
                print(toForm)
            }

            if !NSDictionary(dictionary: fromHeaders).isEqual(to: toHeaders) {
                print("------ Unmatched from Header: ")
                print(fromHeaders)
                print("------ Unmatched to Header: ")
                print(toHeaders)
            }

            if !matched {
                print("------ Unmatched from Expected: ")
                print(fromDict)
                print("------ Unmatched to: ")
                print(toDict)

            }
        }

        return matched
    }
}
