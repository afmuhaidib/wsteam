// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "wsteam",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "wsteam",
            path: "Sources/wsteam",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
