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
        // Resources/prompts 是 shared/prompts 的副本，用 scripts/sync_prompts.sh 同步
        .target(name: "NotBadCore", resources: [.copy("Resources/prompts")]),
        .testTarget(name: "NotBadCoreTests", dependencies: ["NotBadCore"]),
    ]
)
