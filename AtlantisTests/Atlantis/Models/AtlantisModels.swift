//
//  AtlantisModels.swift
//  ProxymanCore
//
//  Created by Nghia Tran on 10/26/20.
//  Copyright © 2020 com.nsproxy.proxy. All rights reserved.
//

import Foundation
#if os(macOS)
import AppKit.NSImage
#elseif os(iOS)
import UIKit.UIImage
#endif

extension KeyedDecodingContainer {
    func decodeWrapper<T>(_ type: T.Type, forKey: K, defaultValue: T) throws -> T
        where T : Decodable {
            do {
                // Catch all error, because sometime the Type is mismatch, so we return the default value
                return try decodeIfPresent(type, forKey: forKey) ?? defaultValue
            } catch {
                return defaultValue
            }
    }
}

extension String {

    public func decodeBase64() -> String? {
        guard let data = Data(base64Encoded: self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var isSchemeSecure: Bool {
      return self == "https" || self == "wss"
    }

    public func toArrayUInt8() -> [UInt8] {
        return Array(self.utf8)
    }
}

public struct AtlantisModels {

    public struct Message: Decodable {

        enum CodingKeys: String, CodingKey {
            case id
            case messageType
            case buildVersion
            case content
        }

        public enum MessageType {
            case connection(ConnectionPackage) // First message, contains: Project, Device metadata
            case traffic(TrafficPackage) // Request/Response log
            case websocket(TrafficPackage)
            case unknown
        }

        // MARK: - Variables

        public let id: String
        public let messageType: MessageType
        public let buildVersion: String?

        // MARK: - Init

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeWrapper(String.self, forKey: .id, defaultValue: "-")
            buildVersion = try container.decodeIfPresent(String.self, forKey: .buildVersion)
            let messageType = try container.decode(String.self, forKey: .messageType)
            if let contentText = try container.decodeIfPresent(String.self, forKey: .content),
                let data = Data(base64Encoded: contentText) {
                switch messageType {
                case "connection":
                    let connectionPackage = try JSONDecoder().decode(ConnectionPackage.self, from: data)
                    self.messageType = .connection(connectionPackage)
                case "traffic":
                    let trafficPackage = try JSONDecoder().decode(TrafficPackage.self, from: data)
                    self.messageType = .traffic(trafficPackage)
                case "websocket":
                    let trafficPackage = try JSONDecoder().decode(TrafficPackage.self, from: data)
                    self.messageType = .websocket(trafficPackage)
                default:
                    self.messageType = .unknown
                    print("[Atlantis] Could not know Message type Unknown")
                }
            } else {
                self.messageType = .unknown
                print("[Atlantis] Could not know Message type Unknown")
            }
        }
    }

    // MARK: - Connection

    public struct ConnectionPackage: Decodable {

        enum CodingKeys: String, CodingKey {
            case device
            case project
            case content
            case icon
        }

        public let device: Device
        public let project: Project
        #if os(macOS)
        public let icon: NSImage?
        #elseif os(iOS)
        public let icon: UIImage?
        #endif

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            device = try container.decodeWrapper(Device.self, forKey: .device, defaultValue: Device(name: "Unknown", model: ""))
            project = try container.decodeWrapper(Project.self, forKey: .project, defaultValue: Project(name: "Unknown", bundleIdentifier: "-"))
            if let imageString = try? container.decodeIfPresent(String.self, forKey: .icon),
                let data = Data(base64Encoded: imageString) {
                #if os(macOS)
                icon = NSImage(data: data)
                #elseif os(iOS)
                icon = UIImage(data: data)
                #endif
            } else {
                icon = nil
            }
        }
    }

    public struct Device: Decodable {

        enum CodingKeys: String, CodingKey {
            case name
            case model
        }

        public let name: String
        public let model: String

        init(name: String, model: String) {
            self.name = name
            self.model = model
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeWrapper(String.self, forKey: .name, defaultValue: "Unknown")
            model = try container.decodeWrapper(String.self, forKey: .model, defaultValue: "")
        }
    }

    public struct Project: Decodable {

        enum CodingKeys: String, CodingKey {
            case name
            case bundleIdentifier
        }

        public let name: String
        public let bundleIdentifier: String

        init(name: String, bundleIdentifier: String) {
            self.name = name
            self.bundleIdentifier = bundleIdentifier
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeWrapper(String.self, forKey: .name, defaultValue: "Unknown")
            bundleIdentifier = try container.decodeWrapper(String.self, forKey: .bundleIdentifier, defaultValue: "")
        }
    }

    // MARK: - Traffic

    public struct TrafficPackage: Decodable {

        enum CodingKeys: String, CodingKey {
            case id
            case request
            case response
            case error
            case responseBodyData
            case startAt
            case endAt
            case packageType
            case websocketMessagePackage
        }

        public enum PackageType: String, Codable {
            case http
            case websocket
        }

        // we don't need "id" in traffic package
        // It's internal usage for the framework
        public let id: String
        public let request: Request
        public let response: Response?
        public let error: CustomError?
        public let responseBodyData: Data?
        public let startAt: TimeInterval
        public let endAt: TimeInterval?
        public let packageType: PackageType
        public let websocketMessagePackage: WebsocketMessagePackage?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeWrapper(String.self, forKey: .id, defaultValue: "-")
            request = try container.decodeWrapper(Request.self, forKey: .request, defaultValue: Request(url: "", method: "", headers: [], body: nil))
            response = try container.decodeIfPresent(Response.self, forKey: .response)
            error = try container.decodeIfPresent(CustomError.self, forKey: .error)
            startAt = try container.decodeWrapper(TimeInterval.self, forKey: .startAt, defaultValue: Date().timeIntervalSince1970)
            endAt = try container.decodeIfPresent(TimeInterval.self, forKey: .endAt)
            packageType = try container.decodeWrapper(PackageType.self, forKey: .packageType, defaultValue: PackageType.http)
            websocketMessagePackage = try container.decodeIfPresent(WebsocketMessagePackage.self, forKey: .websocketMessagePackage)

            if let dataText = try? container.decodeIfPresent(String.self, forKey: .responseBodyData),
                let data = Data(base64Encoded: dataText) {
                responseBodyData = data
            } else {
                responseBodyData = nil
            }
        }
    }

    public struct Header: Decodable {

        enum CodingKeys: String, CodingKey {
            case key
            case value
        }

        let key: String
        let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decodeWrapper(String.self, forKey: .key, defaultValue: "-")
            value = try container.decodeWrapper(String.self, forKey: .value, defaultValue: "-")
        }
    }

    public struct Request: Decodable {

        enum CodingKeys: String, CodingKey {
            case url
            case method
            case headers
            case body
        }

        let url: String
        let method: String
        let headers: [Header]
        let body: Data?

        var isSSL: Bool {
            // Since URL is a full path, we can contruct the URLComponent
            guard let nsURL = URL(string: url),
                  let component = URLComponents(url: nsURL, resolvingAgainstBaseURL: false) else {
                assertionFailure("Should check why we could not init URLComponent from Atlantis")
                return false
            }

            // check scheme to know if it's a secured connection or not
            return component.scheme?.isSchemeSecure ?? false
        }

        init(url: String, method: String, headers: [AtlantisModels.Header], body: Data?) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decodeWrapper(String.self, forKey: .url, defaultValue: "-")
            method = try container.decodeWrapper(String.self, forKey: .method, defaultValue: "-")
            headers = try container.decodeWrapper([Header].self, forKey: .headers, defaultValue: [])
            body = try container.decodeIfPresent(Data.self, forKey: .body)
        }
    }

    public struct Response: Decodable {

        enum CodingKeys: String, CodingKey {
            case statusCode
            case headers
        }

        let statusCode: Int
        let headers: [Header]

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            statusCode = try container.decodeWrapper(Int.self, forKey: .statusCode, defaultValue: 999)
            headers = try container.decodeWrapper([Header].self, forKey: .headers, defaultValue: [])
        }
    }

    public struct CustomError: Decodable {

        enum CodingKeys: String, CodingKey {
            case code
            case message
        }

        let code: Int
        let message: String

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decodeWrapper(Int.self, forKey: .code, defaultValue: 999)
            message = try container.decodeWrapper(String.self, forKey: .message, defaultValue: "Unknown")
        }
    }

    public struct WebsocketMessagePackage: Decodable {

        public enum CodingKeys: String, CodingKey {
            case id
            case createdAt
            case messageType
            case stringValue
            case dataValue
        }

        public enum MessageType: String, Codable {
            case pingPong
            case send
            case receive
            case sendCloseMessage
        }

        public let id: String
        public let createdAt: TimeInterval
        public let messageType: MessageType
        public let stringValue: String?
        public let dataValue: Data?

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
            messageType = try container.decode(MessageType.self, forKey: .messageType)
            stringValue = try container.decodeIfPresent(String.self, forKey: .stringValue)
            dataValue = try container.decodeIfPresent(Data.self, forKey: .dataValue)
        }
    }
}
