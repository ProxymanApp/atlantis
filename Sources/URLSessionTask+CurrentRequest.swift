
import Foundation
#if os(iOS) || os(macOS)
import class AVFoundation.AVAggregateAssetDownloadTask
#endif

extension URLSessionTask {
    var currentRequestSafe: URLRequest? {
        // If sessionTask is AVAggregateAssetDownloadTask,
        // accessing currentRequest crashes with not supported error,
        // so we need to check for it in advance.
        #if os(iOS) || os(macOS)
        if self is AVAggregateAssetDownloadTask {
            return nil
        }
        #endif

        return currentRequest
    }

    var isWebSocketTask: Bool {
        // The new loader's NWURLSessionWebSocketTask only answers to the public class
        if isKind(of: URLSessionWebSocketTask.self) {
            return true
        }
        if let websocketClass = NSClassFromString("__NSURLSessionWebSocketTask") {
            return isKind(of: websocketClass)
        }
        return false
    }
}
