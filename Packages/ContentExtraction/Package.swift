// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ContentExtraction",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "ContentExtraction", targets: ["ContentExtraction"])
    ],
    dependencies: [
        // An HTML parser. The heuristic extractor needs a real DOM to score
        // candidates against; scanning tags with regular expressions loses to
        // the first page with a comment containing a `<div>`.
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.7")
    ],
    targets: [
        .target(
            name: "ContentExtraction",
            dependencies: ["SwiftSoup"],
            resources: [
                .copy("Resources/Readability.js"),
                // Apache 2.0 requires the licence travel with the code.
                .copy("Resources/Readability-LICENSE.md")
            ]
        ),
        .testTarget(
            name: "ContentExtractionTests",
            dependencies: ["ContentExtraction"],
            resources: [.copy("Fixtures")]
        )
    ]
)
