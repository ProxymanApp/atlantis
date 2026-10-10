//
//  Demo.swift
//  AtlantisSwiftUIApp
//

import SwiftUI

/// A tab of the app
enum DemoPage: String, CaseIterable, Identifiable {
    case iOS18
    case iOS26
    case iOS27

    var id: String { rawValue }
}

struct DemoSection: Identifiable {
    let title: String
    let demos: [Demo]

    var id: String { title }
}

/// An API that Atlantis captures, and the method that Atlantis swizzles to capture it
struct Demo: Identifiable {

    enum Requirement {
        case none
        /// URLSession's new loader (usesClassicLoadingMode = false)
        case iOS18_4
        case iOS26
        case iOS26_1
        case iOS27

        var isSatisfied: Bool {
            switch self {
            case .none:
                return true
            case .iOS18_4:
                if #available(iOS 18.4, *) { return true }
                return false
            case .iOS26:
                if #available(iOS 26.0, *) { return true }
                return false
            case .iOS26_1:
                if #available(iOS 26.1, *) { return true }
                return false
            case .iOS27:
                // The iOS 27 SDK (Xcode 27) is required too
                #if compiler(>=6.4)
                if #available(iOS 27.0, *) { return true }
                #endif
                return false
            }
        }

        var label: String {
            switch self {
            case .none: return ""
            case .iOS18_4: return "iOS 18.4+"
            case .iOS26: return "iOS 26+"
            case .iOS26_1: return "iOS 26.1+"
            case .iOS27: return "iOS 27+"
            }
        }
    }

    enum Action {
        /// Send the request, return the status code
        case request(() async throws -> Int)
        /// Show an AsyncImage of the Atlantis logo, loaded with this loader
        case image(URLSessionLoader)
    }

    let id: String
    let title: String
    /// The method that Atlantis swizzles to capture the traffic
    let swizzled: String
    let symbol: String
    let tint: Color
    var requirement: Requirement = .none
    let action: Action
}

enum DemoStatus: Equatable {
    case idle
    case running
    /// The status code is nil if it's unknown, e.g. AsyncImage
    case success(statusCode: Int?)
    case failure(String)
}

// MARK: - Store

@MainActor
final class DemoStore: ObservableObject {

    enum Capture {
        case captured
        case missed
    }

    @Published private var statuses: [Demo.ID: DemoStatus] = [:]
    @Published private var captures: [Demo.ID: Capture] = [:]
    @Published private var runningPages: Set<DemoPage> = []

    /// A new value loads the image again
    @Published private(set) var imageRuns: [Demo.ID: UUID] = [:]

    func status(of demo: Demo) -> DemoStatus {
        return statuses[demo.id] ?? .idle
    }

    func capture(of demo: Demo) -> Capture? {
        return captures[demo.id]
    }

    func isRunning(_ page: DemoPage) -> Bool {
        return runningPages.contains(page)
    }

    func run(_ demo: Demo) async {
        guard demo.requirement.isSatisfied, status(of: demo) != .running else {
            return
        }
        statuses[demo.id] = .running
        captures[demo.id] = nil

        switch demo.action {
        case .request(let send):
            do {
                let statusCode = try await send()
                statuses[demo.id] = .success(statusCode: statusCode)
                verifyCapture(of: demo)
            } catch {
                statuses[demo.id] = .failure(error.localizedDescription)
            }
        case .image:
            // DemoRow shows the image, then calls imageDidLoad or imageDidFail
            imageRuns[demo.id] = UUID()
        }
    }

    func runAll(_ page: DemoPage) async {
        guard !isRunning(page) else {
            return
        }
        runningPages.insert(page)
        for demo in page.sections.flatMap(\.demos) {
            await run(demo)
        }
        runningPages.remove(page)
    }

    func imageDidLoad(_ demo: Demo) {
        guard status(of: demo) == .running else {
            return
        }
        statuses[demo.id] = .success(statusCode: nil)
        verifyCapture(of: demo)
    }

    func imageDidFail(_ demo: Demo, error: Error) {
        guard status(of: demo) == .running else {
            return
        }
        statuses[demo.id] = .failure(error.localizedDescription)
    }

    /// Every request has a `demo` query item, so we know which demo Atlantis captured
    func didCapture(url: String) {
        guard let id = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "demo" })?.value else {
            return
        }
        captures[id] = .captured
    }

    /// Atlantis sends the traffic right after the request finishes, give it a moment
    private func verifyCapture(of demo: Demo) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            if captures[demo.id] == nil, case .success = status(of: demo) {
                captures[demo.id] = .missed
            }
        }
    }
}
