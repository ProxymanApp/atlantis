//
//  NSObject+AtlantisHelper.m
//  atlantis-proxyman
//
//  Created by Nghia Tran on 10/04/2021.
//

#import "AtlantisHelper.h"

@implementation AtlantisHelper

+(id _Nullable) swizzleWebSocketReceiveMessageWithCompleteHandler:(id)handler responseHandler:(void (^_Nullable)(NSString* _Nullable str, NSData* _Nullable data, NSError* _Nullable error)) responseHandler {
    if (@available(iOS 13.0, macOS 10.15, tvOS 13.0, *)) {
            typedef void (^WebSocketHandler) (NSURLSessionWebSocketMessage *message, NSError *error);

        // We need handle in Objc Helper because Xcode doesn't allow to compile with NSURLSessionWebSocketMessage class
        // We get the data/string from NSURLSessionWebSocketMessage and pass back to Atlantis-Swift
        // In objc, it's easer to implement
        WebSocketHandler wrapperHandler = ^(NSURLSessionWebSocketMessage *message, NSError *error) {

            // Pass data to Atlantis Swift
            if (responseHandler) {
                responseHandler([message string], [message data], error);
            }

            // Cast
            WebSocketHandler originalHandler = (WebSocketHandler) handler;

            // Call the original
            originalHandler(message, error);
        };

        return wrapperHandler;
    }
    return nil;
}

@end
