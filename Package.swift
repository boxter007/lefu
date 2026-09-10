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
    ],
    // 钉死 Swift 5 语言模式：代码按 v5 语义编写（GCD + MainActor 混用），
    // CI 的 Swift 6 编译器默认 v6 模式会把并发捕获告警升级成错误
    swiftLanguageVersions: [.v5]
)
