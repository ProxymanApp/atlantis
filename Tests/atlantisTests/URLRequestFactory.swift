//
//  URLRequestFactory.swift
//
//
//  Created by Nghia Tran on 24/7/24.
//

import Foundation

struct URLRequestFactory {

    static func get() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://httpbin.proxyman.app/get?id=123&commpany=proxyman%20LLC&ids[0]=sorted&emoji=%E2%AD%90%EF%B8%8F")!,
                                 cachePolicy: .reloadIgnoringCacheData,
                                 timeoutInterval: 10)
        request.httpMethod = "GET"
        return request
    }
}
