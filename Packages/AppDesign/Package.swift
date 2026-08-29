// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppDesign",
    platforms: [
        .iOS(.v26), .macOS(.v26), .tvOS(.v26), .visionOS(.v26)
    ],
    products: [
        .library(name: "AppDesign", targets: ["AppDesign"])
    ],
    targets: [
        .target(
            name: "AppDesign",
            dependencies: [],
            // Declared explicitly. Undeclared, SwiftPM warns that it does not
            // know what these are and skips them, and the asset symbols the
            // theme is built from never get generated.
            resources: [
                .process("All Platforms/Color/Color.xcassets"),
                .process("All Platforms/Image/Icon/Icon.xcassets"),
                .process("All Platforms/Image/Illustration/Illustration.xcassets")
            ]
        )
    ]
)
