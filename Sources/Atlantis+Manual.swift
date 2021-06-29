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


    /// Helper func to convert GRPC message to Atlantis format that could show on Proxyman app as a HTTP Message
    /// - Parameters:
    ///   - url: The url of the grpc message to distinguish each message
    ///   - requestObject: Request Data for the Request, use `try? request.jsonUTF8Data()` for this.
    ///   - responseObject: Response object for the Response, use `try? response.jsonUTF8Data()` for this.
    ///   - success: success state. Get from `CallResult.success`
    ///   - statusCode: statusCode state. Get from `CallResult.statusCode`
    ///   - statusMessage: statusMessage state. Get from `CallResult.statusMessage`
    ///   - HPACKHeadersRequest: Transformed request headers from gRPC. Get it from `callOptions?.customMetadata`
    ///   - HPACKHeadersResponse: Transformed response headers from gRPC. Get it from `CallResult.trailingMetadata` or `CallResult.initialMetadata`
    public class func addGRPC(url: String,
                                 requestObject: Data?,
                                 responseObject: Data?,
                                 success: Bool,
                                 statusCode: Int,
                                 statusMessage: String?,
                                 HPACKHeadersRequest: [Header]? = nil,
                                 HPACKHeadersResponse: [Header]? = nil){

        let request = Request(url: url, method: "GRPC", headers: HPACKHeadersRequest ?? [], body: requestObject)

        // Wrap the CallResult to Response Headers
        var headers =  [Header(key: "success", value: "\(success ? "true" : "false")"),
                        Header(key: "statusCode", value: GRPCStatusCode(rawValue: statusCode)?.description ?? "Unknown status Code \(statusCode)"),
        				Header(key: "statusMessage", value: statusMessage ?? "nil")]
        headers.append(contentsOf: HPACKHeadersResponse ?? [])
        let response = Response(statusCode: success ? 200 : 503, headers: headers)
        self.add(request: request, response: response, responseBody: responseObject)
    }
}
