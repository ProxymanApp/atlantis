// swift-tools-version:6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Atlantis",
    platforms: [.macOS(.v10_15),
                .iOS(.v13),
                .tvOS(.v13),
                .watchOS(.v10),
                .visionOS(.v1)],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "Atlantis",
            targets: ["Atlantis"]),
    ],
    dependencies: [
        // Temporary integration source. Switch to the first official release containing
        // https://github.com/grpc/grpc-swift-2/pull/51 before tagging Atlantis 2.0.
        .package(url: "https://github.com/NghiaTranUIT/grpc-swift-2.git",
                 branch: "codex/client-diagnostics-observer")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "Atlantis",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2")
            ],
            path: "Sources",
            resources: [.copy("PrivacyInfo.xcprivacy")])
        ,
        .testTarget(
            name: "AtlantisTests",
            dependencies: [
                "Atlantis",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCInProcessTransport", package: "grpc-swift-2")
            ],
            path: "Tests/atlantisTests",
            resources: [.process("Resources/sse-server.js")])
    ],
    swiftLanguageModes: [.v5]
)
