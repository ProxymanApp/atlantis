//
//  DemoListView.swift
//  AtlantisSwiftUIApp
//

import SwiftUI

/// A tab: the APIs that Atlantis captures, grouped
struct DemoListView: View {

    let page: DemoPage
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(page.sections) { section in
                    Section(section.title) {
                        ForEach(section.demos) { demo in
                            DemoRow(demo: demo)
                        }
                    }
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if store.isRunning(page) {
                        ProgressView()
                    } else {
                        Button("Run All") {
                            Task { await store.runAll(page) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Row

/// The title and the method that Atlantis swizzles. Tap to send the request
private struct DemoRow: View {

    let demo: Demo
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        let status = store.status(of: demo)

        Button {
            Task { await store.run(demo) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: demo.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(demo.tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(demo.title)
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if case .image(let loader) = demo.action, let run = store.imageRuns[demo.id] {
                            // The image is the status
                            DemoAsyncImage(demo: demo, loader: loader, run: run)
                                .overlay(alignment: .topTrailing) {
                                    DemoCaptureMark(capture: store.capture(of: demo))
                                        .offset(x: 6, y: -6)
                                }
                        } else {
                            DemoStatusBadge(status: status, capture: store.capture(of: demo), requirement: demo.requirement)
                        }
                    }
                    Text(DemoText.wrappable(demo.swizzled))
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(2)
                    if case .failure(let message) = status {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }
            }
        }
        .disabled(!demo.requirement.isSatisfied)
    }
}

/// The status code. Green with ✓ when Atlantis captured the request, orange when it didn't
private struct DemoStatusBadge: View {

    let status: DemoStatus
    let capture: DemoStore.Capture?
    let requirement: Demo.Requirement

    var body: some View {
        if !requirement.isSatisfied {
            Text(requirement.label)
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
        } else {
            switch status {
            case .idle:
                EmptyView()
            case .running:
                ProgressView()
            case .success(let statusCode):
                HStack(spacing: 3) {
                    if capture == .captured {
                        Image(systemName: "checkmark")
                    }
                    Text(statusCode.map { "\($0)" } ?? "OK")
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color, in: Capsule())
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private var color: Color {
        switch capture {
        case .captured: return .green
        case .missed: return .orange
        case nil: return Color(.systemGray3)
        }
    }
}

/// ✓ when Atlantis captured the request, ! when it didn't
private struct DemoCaptureMark: View {

    let capture: DemoStore.Capture?

    var body: some View {
        switch capture {
        case .captured:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
        case .missed:
            Image(systemName: "exclamationmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .orange)
        case nil:
            EmptyView()
        }
    }
}

enum DemoText {

    /// Long selectors wrap at ":" and long class names between words, not in the middle of a word.
    /// "-[" stays on the same line
    static func wrappable(_ text: String) -> String {
        let isClassName = !text.contains(" ")
        var result = ""
        var previous: Character?
        for character in text {
            if isClassName, let previous = previous, previous.isLowercase, character.isUppercase {
                result.append("\u{200B}")
            }
            if character == "[", previous == "-" {
                result.append("\u{2060}")
            }
            result.append(character)
            if character == ":" {
                result.append("\u{200B}")
            }
            previous = character
        }
        return result
    }
}

// MARK: - AsyncImage (iOS 27)

/// iOS 27: AsyncImage loads a URLRequest, with the URLSession from asyncImageURLSession(_:)
private struct DemoAsyncImage: View {

    let demo: Demo
    let loader: URLSessionLoader
    /// Each run has a new URL, so the image isn't from the cache
    let run: UUID
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        // AsyncImage(request:) is in the iOS 27 SDK (Xcode 27)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            asyncImage
                .frame(width: 64, height: 27)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(.separator)))
                .id(run)
        }
        #endif
    }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    @ViewBuilder
    private var asyncImage: some View {
        let image = AsyncImage(request: request) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .onAppear { store.imageDidLoad(demo) }
            case .failure(let error):
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
                    .onAppear { store.imageDidFail(demo, error: error) }
            default:
                ProgressView()
                    .controlSize(.small)
            }
        }
        switch loader {
        case .classic:
            image
        case .new:
            image.asyncImageURLSession(DemoRequests.newLoaderImageSession)
        }
    }
    #endif

    private var request: URLRequest {
        var request = URLRequest(url: DemoRequests.logoURL(demo: demo.id, queryItems: [URLQueryItem(name: "run", value: run.uuidString)]))
        // A URLRequest can have headers, a URL can't
        request.setValue(demo.title, forHTTPHeaderField: "X-Atlantis-Demo")
        return request
    }
}
