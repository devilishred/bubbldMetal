// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BubbldMetal",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "BubbldMetal", targets: ["BubbldMetal"]),
    ],
    targets: [
        // The .metal file under Sources/ is compiled automatically into
        // `default.metallib` inside the target's resource bundle, which also
        // synthesizes `Bundle.module`. No `resources:` entry is needed.
        .target(name: "BubbldMetal"),
        .testTarget(name: "BubbldMetalTests", dependencies: ["BubbldMetal"]),
    ],
    // Stay in Swift 5 language mode to avoid strict-concurrency friction on the UI types.
    swiftLanguageModes: [.v5]
)
