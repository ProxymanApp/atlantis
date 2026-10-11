
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

    private static let markLock = NSLock()

    /// Whether the task is marked with the key, without a lock
    func isMarked(_ key: UnsafeRawPointer) -> Bool {
        return objc_getAssociatedObject(self, key) != nil
    }

    /// Mark the task with the key, e.g. to report something once per task.
    /// Return false if it's already marked
    func markOnce(_ key: UnsafeRawPointer) -> Bool {
        guard !isMarked(key) else {
            return false
        }
        URLSessionTask.markLock.lock()
        defer { URLSessionTask.markLock.unlock() }
        guard !isMarked(key) else {
            return false
        }
        objc_setAssociatedObject(self, key, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return true
    }
}
