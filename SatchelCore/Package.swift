// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SatchelCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SatchelCore", targets: ["SatchelCore"])
    ],
    targets: [
        .target(
            name: "SatchelCore",
            path: "Sources/SatchelCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SatchelCoreTests",
            dependencies: ["SatchelCore"],
            path: "Tests/SatchelCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
