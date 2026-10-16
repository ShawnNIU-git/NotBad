// swift-tools-version:5.9
// 不依赖 UIKit 的核心逻辑，可在 macOS 和 Linux 上用 `swift test` 测试。

import PackageDescription

let package = Package(
    name: "NotBadCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NotBadCore", targets: ["NotBadCore"]),
    ],
    targets: [
        .target(name: "NotBadCore"),
        .testTarget(name: "NotBadCoreTests", dependencies: ["NotBadCore"]),
    ]
)
