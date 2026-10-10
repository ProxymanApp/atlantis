//
//  DemoListView.swift
//  AtlantisSwiftUIApp
//

import SwiftUI

/// A tab: the APIs that Atlantis swizzles, grouped
struct DemoListView: View {

    let page: DemoPage
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DemoPageHeader(page: page)
                }

                ForEach(page.sections) { section in
                    Section {
                        ForEach(section.demos) { demo in
                            DemoRow(demo: demo)
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if let footer = section.footer {
                            Text(DemoText.wrappable(footer))
                        }
                    }
                }
            }
            .navigationTitle(page.title)
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

// MARK: - Header

private struct DemoPageHeader: View {

    let page: DemoPage

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "\(page.symbol).fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, page.tint.gradient)

            VStack(alignment: .leading, spacing: 6) {
                Text(page.headline)
                    .font(.headline)
                Text(page.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Running on \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Row

private struct DemoRow: View {

    let demo: Demo
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        let status = store.status(of: demo)

        Button {
            Task { await store.run(demo) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                DemoIcon(symbol: demo.symbol, tint: demo.tint)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(demo.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color(.label))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        DemoStatusBadge(status: status, requirement: demo.requirement)
                    }
                    .frame(minHeight: 32)

                    Text(demo.api)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                        Text(DemoText.wrappable(demo.swizzled))
                            .lineLimit(2)
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(demo.tint)

                    DemoStatusMessage(demo: demo, status: status)

                    if case .image(let path, let loader) = demo.action, let run = store.imageRuns[demo.id] {
                        DemoAsyncImage(demo: demo, path: path, loader: loader, run: run)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .disabled(!demo.requirement.isSatisfied)
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

private struct DemoIcon: View {

    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Below the swizzled method: whether Atlantis captured the request, or the error
private struct DemoStatusMessage: View {

    let demo: Demo
    let status: DemoStatus
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        switch status {
        case .success(_, let summary, _):
            HStack(spacing: 4) {
                switch store.capture(of: demo) {
                case .captured:
                    Image(systemName: "checkmark.seal.fill")
                    Text("Captured by Atlantis")
                case .missed:
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Not captured")
                case nil:
                    EmptyView()
                }
                if let summary = summary {
                    Text(store.capture(of: demo) == nil ? summary : "· \(summary)")
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .font(.caption)
            .foregroundStyle(store.capture(of: demo) == .missed ? Color.orange : Color.green)
            .lineLimit(1)
            .padding(.top, 2)
        case .failure(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .padding(.top, 2)
        case .idle, .running:
            EmptyView()
        }
    }
}

private struct DemoStatusBadge: View {

    let status: DemoStatus
    let requirement: Demo.Requirement

    var body: some View {
        if !requirement.isSatisfied {
            Text(requirement.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: Capsule())
        } else {
            switch status {
            case .idle:
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            case .running:
                ProgressView()
            case .success(let statusCode, _, let duration):
                VStack(alignment: .trailing, spacing: 4) {
                    Text(statusCode.map { "\($0)" } ?? "OK")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((statusCode ?? 200) < 400 ? Color.green.gradient : Color.orange.gradient, in: Capsule())
                    Text(Self.format(duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color(.secondaryLabel))
                }
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
        }
    }

    private static func format(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int(duration * 1000)) ms"
        }
        return String(format: "%.1f s", duration)
    }
}

// MARK: - AsyncImage (iOS 27)

/// iOS 27: AsyncImage loads a URLRequest, with the URLSession from asyncImageURLSession(_:)
private struct DemoAsyncImage: View {

    let demo: Demo
    let path: String
    let loader: URLSessionLoader
    /// Each run has a new URL, so the image isn't from the cache
    let run: UUID
    @EnvironmentObject private var store: DemoStore

    var body: some View {
        // AsyncImage(request:) is in the iOS 27 SDK (Xcode 27)
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            asyncImage
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background(Color(.quaternarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .onAppear { store.imageDidFail(demo, error: error) }
            default:
                ProgressView()
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
        let url = DemoRequests.url(path, demo: demo.id, queryItems: [URLQueryItem(name: "run", value: run.uuidString)])
        var request = URLRequest(url: url)
        // A URLRequest can have headers, a URL can't
        request.setValue(demo.api, forHTTPHeaderField: "X-Atlantis-Demo")
        return request
    }
}
