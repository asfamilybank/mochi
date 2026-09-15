// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v26)],
    products: [
        // Consumed by the Xcode app target, which links MochiCore as a local package product
        // rather than recompiling its sources (ADR-0014). `swift build`/`swift test` don't need
        // this entry; without it the package exposes nothing and Xcode reports the product as
        // missing.
        .library(name: "MochiCore", targets: ["MochiCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0")
    ],
    targets: [
        .target(
            name: "MochiCore",
            dependencies: ["TOMLKit"]
        ),
        .executableTarget(
            name: "Mochi",
            dependencies: ["MochiCore"]
        ),
        .testTarget(
            name: "MochiCoreTests",
            dependencies: ["MochiCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
