import SwiftUI
import LefuCore

// MARK: - 入口
@main
struct LefuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var session: SessionController

    init() {
        let s = AppSettings()
        let c = SessionController(settings: s)
        _settings = StateObject(wrappedValue: s)
        _session = StateObject(wrappedValue: c)
        // AppDelegate 在 applicationDidFinishLaunching 里拿不到 @StateObject，
        // 旧系统装菜单栏桥接需要这两个实例，故留一份静态引用。
        LefuApp.sharedContext = (s, c)
    }

    /// 供 AppDelegate 使用的实例引用（仅启动期写入一次）
    private(set) static var sharedContext: (settings: AppSettings, session: SessionController)?

    var body: some Scene {
        // —— 单一代码路径，刻意不做版本分叉 ——
        //
        // 踩过的坑（详见 CHANGELOG 1.0.5 与 MainWindowKeeper 注释）：
        //   · `SceneBuilder` 无 `buildEither`，Scene 里（含 App.body）不能写任何 `if`；
        //   · 把分叉挪进普通函数用 `some Scene` 返回也不行：opaque 返回类型要求所有
        //     return 的底层类型一致，而 Window 与 WindowGroup 是不同类型。编译器在
        //     某些情况下不报错却生成会崩的代码，实测段错误：
        //       EXC_BAD_ACCESS KERN_INVALID_ADDRESS at 0x10
        //       swift_retain ← initializeWithCopy for LefuSceneContent
        //       ← initializeWithCopy for Window ← LefuApp.body.getter
        //
        // 最终方案：主窗一律 WindowGroup（12 与 13+ 通用）；
        // 菜单栏一律 AppKit 的 MenuBarBridge（NSStatusItem + NSPopover）；
        // 主窗关闭由 MainWindowKeeper 转成「隐藏」，因此无需 openWindow（13+）重建。
        WindowGroup("乐府") {
            RootView(settings: settings, session: session)
                .frame(minWidth: 900, minHeight: 560)
                .frame(idealWidth: 1080, idealHeight: 675)
                .preferredColorScheme(colorScheme)
                .environment(\.lefuTheme, theme)
        }
        .windowStyle(.hiddenTitleBar)
    }

    /// 主窗判定：排除菜单栏面板与系统 30pt 高的菜单栏条（同为 layer 0，但不是主窗）。
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && $0.frame.height > 200 }
    }

    /// 显示主窗：有窗就前置（含从最小化/隐藏恢复）。
    ///
    /// 不需要 `openWindow`（13+）：主窗由 MainWindowKeeper 保活，
    /// 关闭只是 orderOut，窗口对象始终存在，makeKeyAndOrderFront 即可恢复。
    static func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard let win = mainWindow else {
            Diag.log("WIN 未找到主窗，无法前置")
            return
        }
        if win.isMiniaturized { win.deminiaturize(nil) }
        win.makeKeyAndOrderFront(nil)
    }

    /// AppDelegate（Dock 点击 / open -a）拿不到视图环境，转成通知由菜单栏桥接代劳。
    static func showMain() {
        NotificationCenter.default.post(name: .lefuShowMain, object: nil)
    }

    private var colorScheme: ColorScheme? {
        LefuThemeFactory.colorScheme(for: settings)
    }

    /// 主题统一由 LefuThemeFactory 派生（主窗与菜单栏面板共用同一份逻辑）
    private var theme: LefuTheme {
        LefuThemeFactory.make(settings: settings, session: session)
    }
}

extension Notification.Name {
    /// 请求显示 / 重建主窗
    static let lefuShowMain = Notification.Name("lefu.showMain")
}

/// 常驻菜单栏图标由 AppKit 的 `MenuBarBridge` 实现（见 Views/MenuBarBridge.swift），
/// 因为 SwiftUI 的 `MenuBarExtra` 是 macOS 13+ API，而乐府最低支持 macOS 12。
/// 面板本体 `MenuBarPanel` 仍是普通 SwiftUI View，界面代码零重复。

// MARK: - 委托
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 菜单栏常驻（AppKit 路径，macOS 12 与 13+ 共用）
    private var menuBarBridge: MenuBarBridge?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1) 菜单栏常驻面板
        if let (settings, session) = LefuApp.sharedContext {
            let bridge = MenuBarBridge()
            bridge.install(settings: settings, session: session)
            menuBarBridge = bridge
        }

        // 2) 主窗保活：关闭转为隐藏，保证「打开主窗」随时可用
        //    （macOS 12 拿不到 openWindow，故不能依赖「关掉再重建」）
        DispatchQueue.main.async {
            if let win = LefuApp.mainWindow {
                MainWindowKeeper.install(on: win)
            }
        }

        // 3) 启动时把主窗校准到 16:10 参考画幅（SwiftUI 的窗口框架记忆按视图链存取，
        //    布局一改就换键失效，容易恢复成奇怪尺寸；这里统一校准，容差 2%）
        DispatchQueue.main.async {
            guard let win = LefuApp.mainWindow else { return }
            let f = win.frame
            guard abs(f.width / f.height - 1.6) > 0.02 else { return }
            let size = NSSize(width: 1080, height: 675)
            let origin = NSPoint(x: f.midX - size.width / 2,
                                 y: f.midY - size.height / 2)
            win.setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }
    // 有关窗不退出：进程常驻菜单栏，挂机监听才能后台跑
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Dock 点图标 / open -a：唤回主窗
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LefuApp.revealMainWindow()
        return true
    }
}
