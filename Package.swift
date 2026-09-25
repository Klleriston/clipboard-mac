// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "macUtil",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClipboardKit"),
        // Descomentado na Task 4, quando main.swift existir: SwiftPM falha em
        // um alvo que ainda não tem nenhum arquivo .swift.
        // .executableTarget(name: "macUtil", dependencies: ["ClipboardKit"]),
        .testTarget(name: "ClipboardKitTests", dependencies: ["ClipboardKit"]),
    ]
)
