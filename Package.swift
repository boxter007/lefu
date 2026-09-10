// swift-tools-version:5.9
// 乐府 — 汽水音乐内录归档 Mac App
import PackageDescription

let package = Package(
    name: "乐府",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "乐府",
            path: "Sources/Lefu"
        )
    ]
)
