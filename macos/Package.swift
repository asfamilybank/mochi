// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v26)],
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
