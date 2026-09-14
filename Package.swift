// swift-tools-version:5.9
// 乐府 — 汽水音乐内录归档 Mac App
import PackageDescription

let package = Package(
    name: "乐府",
    // 最低支持 macOS 12（Monterey）。
    //
    // 13+ 独有的 Window(_:id:) / MenuBarExtra 一律不用：主窗用 WindowGroup、
    // 菜单栏用 AppKit 的 MenuBarBridge（NSStatusItem + NSPopover），
    // 于是全应用只有一条代码路径，不需要任何版本分叉。
    // （分叉写法会让 Scene 的 opaque 返回类型不匹配并生成会崩的代码，
    //   详见 Sources/Lefu/LefuApp.swift 顶部说明与 CHANGELOG 1.0.5。）
    //
    // 注意：这里只是 SwiftPM 的声明，真正决定 Mach-O minos 的是构建时的
    // MACOSX_DEPLOYMENT_TARGET（见 scripts/build_app.sh），两者必须一致。
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "LefuCore",
            path: "Sources/LefuCore"
        ),
        .executableTarget(
            name: "乐府",
            dependencies: ["LefuCore"],
            path: "Sources/Lefu"
        ),
        .testTarget(
            name: "LefuCoreTests",
            dependencies: ["LefuCore"],
            path: "Tests/LefuCoreTests"
        )
    ],
    // 钉死 Swift 5 语言模式：代码按 v5 语义编写（GCD + MainActor 混用），
    // CI 的 Swift 6 编译器默认 v6 模式会把并发捕获告警升级成错误
    swiftLanguageVersions: [.v5]
)
