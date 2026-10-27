// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Recommender",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Recommender",
            path: "Sources/Recommender",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
