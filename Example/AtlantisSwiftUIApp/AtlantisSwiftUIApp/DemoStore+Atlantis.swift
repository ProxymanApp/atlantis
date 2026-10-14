//
//  DemoStore+Atlantis.swift
//  AtlantisSwiftUIApp
//

import Foundation

#if DEBUG
import Atlantis

extension DemoStore: AtlantisDelegate {

    /// Show on each row whether Atlantis captures the request
    func startObservingAtlantis() {
        Atlantis.setDelegate(self)
    }

    nonisolated func atlantisDidHaveNewPackage(_ package: TrafficPackage) {
        let url = package.request.url
        Task { @MainActor in
            self.didCapture(url: url)
        }
    }
}
#else
extension DemoStore {

    func startObservingAtlantis() {}
}
#endif
