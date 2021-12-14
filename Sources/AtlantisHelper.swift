import Foundation

/*
 +(id _Nullable) swizzleWebSocketReceiveMessageWithCompleteHandler:(id)handler responseHandler:(void (^_Nullable)(NSString* _Nullable str, NSData* _Nullable data, NSError* _Nullable error)) responseHandler {
     typedef void (^WebSocketHandler) (NSURLSessionWebSocketMessage *message, NSError *error);

     // We need to handle in Objc Helper because Xcode doesn't allow to compile with NSURLSessionWebSocketMessage class
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
 */

@objc(AtlantisHelper)
class AtlantisHelper: NSObject {
    static let dataSelector: String = "data"
    static let stringSelector: String = "string"

    @objc
    static func swizzleWebSocketReceiveMessage(
        withCompleteHandler handler: AnyObject,
        responseHandler: ((String?, Data?, Error?) -> Void)?
    ) -> AnyObject? {
        typealias WebSocketHandler = @convention(block) (NSObject?, NSError?) -> Void

        // Avoid fatal error by comparing type sizes before cast.
        // Not really a "safeguard" as size doesn't really mean anything.
        // At least it's something.
        guard MemoryLayout.size(ofValue: handler) == MemoryLayout<WebSocketHandler>.size else {
            return nil
        }

        // Here be dragons.
        let originalHandler = unsafeBitCast(handler, to: WebSocketHandler.self)

        let wrapperHandler: WebSocketHandler = { message, error in
            // If message is not NSURLSessionWebSocketMessage, pass it through (hopefully unchanged).
            if let message = message, NSStringFromClass(type(of: message)) == "NSURLSessionWebSocketMessage" {
                if let responseHandler = responseHandler {
                    let body: (string: String?, data: Data?) = {
                        // Basically "switch message as? URLSessionWebSocketTask.Message"
                        if let data = message.perform(
                            Selector(Self.dataSelector)
                        )?.takeUnretainedValue() as? Data {
                            return (nil, data)
                        }
                        if let string = message.perform(
                            Selector(Self.stringSelector)
                        )?.takeUnretainedValue() as? String {
                            return (string, nil)
                        }

                        // And default.
                        assertionFailure("Have NSURLSessionWebSocketMessage but can neither get data nor string.")
                        return (nil, nil)
                    }()
                    responseHandler(body.string, body.data, error)
                }
            }

            originalHandler(message, error)
        }

        return wrapperHandler as AnyObject
    }
}
