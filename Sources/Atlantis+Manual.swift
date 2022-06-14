//
//  Atlantis+Manual.swift
//  Atlantis
//
//  Created by Nghia Tran on 11/7/20.
//

import Foundation

extension Atlantis {

    /// Handy func to manually add Request & Response to Atlantis, then sending to Proxyman app for inspecting.
    /// It's useful if your app makes HTTP Request that not using URLSession e.g. Swift-NIO-GRPC, C++ Network library, ...
    /// - Parameters:
    ///   - request: Request that needs send to Proxyman
    ///   - response: Response that needs send to Proxyman
    ///   - responseBody: The body Data of the response
    public class func add(request: URLRequest,
                          response: URLResponse,
                          responseBody: Data?) {
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
    public class func add(request: URLRequest,
                          error: Error) {
        guard let package = TrafficPackage.buildRequest(urlRequest: request, error: error) else {
            print("[Atlantis][Error] Could not build TrafficPackage from manual input. Please contact the author!")
            return
        }

        // Compose and send the message to Proxyman
        Atlantis.shared.startSendingMessage(package: package)
    }


    /// Handy func to manually add Atlantis' Request & Response, then sending to Proxyman for inspecting
    /// It's useful if your Request & Response are not URLRequest and URLResponse
    /// - Parameters:
    ///   - request: Atlantis' request model
    ///   - response: Atlantis' response model
    ///   - responseBody: The body data of the response
    public class func add(request: Request,
                          response: Response,
                          responseBody: Data?) {
        // Build package from raw given input
        let package = TrafficPackage(id: UUID().uuidString, request: request, response: response, responseBodyData: responseBody)

        // Compose and send the message to Proxyman
        Atlantis.shared.startSendingMessage(package: package)
    }


    /// Helper func to convert unary GRPC message to Atlantis format that could show on Proxyman app as a HTTP Message
    /// - Parameters:
    ///   - url: The url of the grpc message to distinguish each message
    ///   - requestObject: Request Data for the Request, use `try? request.jsonUTF8Data()` for this.
    ///   - responseObject: Response object for the Response, use `try? response.jsonUTF8Data()` for this.
    ///   - success: success state. Get from `CallResult.success`
    ///   - statusCode: statusCode state. Get from `CallResult.statusCode`
    ///   - statusMessage: statusMessage state. Get from `CallResult.statusMessage`
    ///   - startedAt: when the request started
    ///   - endedAt: when the request ended
    ///   - HPACKHeadersRequest: Transformed request headers from gRPC. Get it from `callOptions?.customMetadata`
    ///   - HPACKHeadersResponse: Transformed response headers from gRPC. Get it from `CallResult.trailingMetadata` or `CallResult.initialMetadata`
    public class func addGRPCUnary(path: String,
                            requestObject: Data?,
                            responseObject: Data?,
                            success: Bool,
                            statusCode: Int,
                            statusMessage: String?,
                            startedAt: Date?,
                            endedAt: Date?,
                            HPACKHeadersRequest: [Header] = [],
                            HPACKHeadersResponse: [Header] = []) {
        let request = Request(url: path, method: "GRPC", headers: HPACKHeadersRequest, body: requestObject)

        // Wrap the CallResult to Response Headers
        var headers = [Header(key: "success", value: "\(success ? "true" : "false")"),
                       Header(key: "statusCode", value: GRPCStatusCode(rawValue: statusCode)?.description ?? "Unknown status Code \(statusCode)"),
                       Header(key: "statusMessage", value: statusMessage ?? "nil")]
        headers.append(contentsOf: HPACKHeadersResponse)
        let response = Response(statusCode: success ? 200 : 503, headers: headers)

        // Build package from raw given input
        let package = TrafficPackage(id: UUID().uuidString,
                                     request: request,
                                     response: response,
                                     responseBodyData: responseObject,
                                     startAt: startedAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                                     endAt: endedAt?.timeIntervalSince1970)

        // Compose and send the message to Proxyman
        Atlantis.shared.startSendingMessage(package: package)
    }

    /// Helper func to convert streaming GRPC messages to Atlantis format that could show up on Proxyman as WebSockets
    /// - Parameters:
    ///   - id: UUID of th request to identify it for WebSockts
    ///   - message: The WebSocketMessage, it's plain data or a string
    ///   - success: success state. Get from `CallResult.success`
    ///   - statusCode: statusCode state. Get from `CallResult.statusCode`
    ///   - statusMessage: statusMessage state. Get from `CallResult.statusMessage`
    ///   - streamingType: Determines the stremaing type. `client`, `server` or `biderectional`. Extract it from the interceptor context
    ///   - type: The WebSocket Message Type, we are mostly using `send` and `receive` for determine the direction
    ///   - startedAt: when the request started
    ///   - endedAt: when the request ended
    ///   - HPACKHeadersRequest: Transformed request headers from gRPC. Get it from `callOptions?.customMetadata`
    ///   - HPACKHeadersResponse: Transformed response headers from gRPC. Get it from `CallResult.trailingMetadata` or `CallResult.initialMetadata`
    public class func addGRPCStreaming(id: UUID,
                                path: String,
                                message: WebsocketMessagePackage.Message,
                                success: Bool,
                                statusCode: Int,
                                statusMessage: String?,
                                streamingType: GRPCStreamingType,
                                type: WebsocketMessagePackage.MessageType,
                                startedAt: Date?,
                                endedAt: Date?,
                                HPACKHeadersRequest: [Header] = [],
                                HPACKHeadersResponse: [Header] = []) {
        let request: Request
        switch streamingType
        {
        case .client:
            request = Request(url: path, method: "GRPC", headers: HPACKHeadersRequest, body: nil)
        case .server:
            request = Request(url: path, method: "GRPC", headers: HPACKHeadersRequest, body: message.optionalData)
        case .bidirectional:
            request = Request(url: path, method: "GRPC", headers: HPACKHeadersRequest, body: nil)
        }
        // Wrap the CallResult to Response Headers
        var headers = [Header(key: "success", value: "\(success ? "true" : "false")"),
                       Header(key: "statusCode", value: GRPCStatusCode(rawValue: statusCode)?.description ?? "Unknown status Code \(statusCode)"),
                       Header(key: "statusMessage", value: statusMessage ?? "nil")]
        headers.append(contentsOf: HPACKHeadersResponse)
        let response = Response(statusCode: success ? 200 : 503, headers: headers)
        let responseObject: Data? = {
            switch streamingType {
            case .client:
                return message.optionalData
            case .server:
                return nil
            case .bidirectional:
                return nil
            }
        }()
        let package = TrafficPackage(id: id.uuidString,
                                     request: request,
                                     response: response,
                                     responseBodyData: responseObject,
                                     packageType: .websocket,
                                     startAt: startedAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                                     endAt: endedAt?.timeIntervalSince1970)
        switch (streamingType, type) {
        case (.client, .send),
             (.bidirectional, .send),
             (_, .pingPong),
             (_, .receive),
             (_, .sendCloseMessage):
            package.setWebsocketMessagePackage(package: .init(id: id.uuidString,
                                                              message: message,
                                                              messageType: type))
        case (.server, .send):
            break
        }
        Atlantis.shared.startSendingWebsocketMessage(package)
    }

    public enum GRPCStreamingType {
        case client
        case server
        case bidirectional
    }
}

extension WebsocketMessagePackage.Message {
    var optionalData: Data? {
        switch self {
        case .data(let data):
            return data
        case .string(let string):
            return string.data(using: .utf8)
        }
    }
}
