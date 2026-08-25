// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FeedIngest",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "FeedIngest", targets: ["FeedIngest"])
    ],
    dependencies: [
        // Parses RSS 2.0, Atom and JSON Feed. It dropped RSS 1.0/RDF in 10.x,
        // so `RDFFeedParser` in this package covers that format.
        .package(url: "https://github.com/nmdias/FeedKit.git", from: "10.4.0")
    ],
    targets: [
        .target(
            name: "FeedIngest",
            dependencies: [
                .product(name: "FeedKit", package: "FeedKit")
            ]
        ),
        .testTarget(
            name: "FeedIngestTests",
            dependencies: ["FeedIngest"],
            resources: [.copy("Fixtures")]
        )
    ]
)
