
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
}
