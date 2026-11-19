// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TelepAIth",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TelepAIth",
            path: "Sources/TelepAIth"
        )
    ]
)
