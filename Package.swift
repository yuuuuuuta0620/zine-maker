// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZineMaker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ZineMaker",
            path: "Sources/ZineMaker",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
