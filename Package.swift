// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TextTool",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TextToolCore"),
        .executableTarget(name: "TextTool", dependencies: ["TextToolCore"]),
        .testTarget(name: "TextToolCoreTests", dependencies: ["TextToolCore"]),
    ]
)
