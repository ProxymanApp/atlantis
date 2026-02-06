import Foundation
import Atlantis

@objc(AtlantisReactNative)
class AtlantisReactNative: NSObject {

    // Track running state locally since Atlantis.isEnabled is internal.
    private static var isStarted = false

    @objc static func requiresMainQueueSetup() -> Bool {
        return false
    }

    /// Start Atlantis and begin capturing HTTP/HTTPS traffic.
    /// Traffic is forwarded to the Proxyman macOS app over the local network.
    @objc(start:)
    func start(_ hostName: String?) {
        let resolvedHostName = (hostName?.isEmpty ?? true) ? nil : hostName
        Atlantis.start(hostName: resolvedHostName)
        AtlantisReactNative.isStarted = true
    }

    /// Stop Atlantis and cease capturing traffic.
    @objc(stop)
    func stop() {
        Atlantis.stop()
        AtlantisReactNative.isStarted = false
    }

    /// Check if Atlantis is currently running.
    @objc(isRunning:reject:)
    func isRunning(
        _ resolve: @escaping RCTPromiseResolveBlock,
        reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(AtlantisReactNative.isStarted)
    }
}
