// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "StreamQuery",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "StreamQuery", targets: ["StreamQuery"])
    ],
    targets: [
        // Deliberately dependency-free and free of I/O. The grammar is the part
        // of this app most likely to be quietly wrong, and it can only be held
        // to that standard if it can be tested without a store or a screen.
        .target(name: "StreamQuery"),
        .testTarget(name: "StreamQueryTests", dependencies: ["StreamQuery"])
    ]
)
