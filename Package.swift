// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "macUtil",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClipboardKit"),
        .executableTarget(name: "macUtil", dependencies: ["ClipboardKit"]),
        .testTarget(name: "ClipboardKitTests", dependencies: ["ClipboardKit"]),
    ]
)
