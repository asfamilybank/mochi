// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v13)],
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
    ]
)
