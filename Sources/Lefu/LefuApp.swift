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
    }

    var body: some Scene {
        Window("乐府", id: "main") {
            RootView(settings: settings, session: session)
                .frame(minWidth: 900, minHeight: 560)
                .frame(idealWidth: 1080, idealHeight: 675)
                .preferredColorScheme(colorScheme)
                .environment(\.lefuTheme, theme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 675) // 16:10 参考画幅
        .windowResizability(.contentMinSize)

        // 菜单栏常驻：迷你控制台面板（状态卡 + 主按钮 + 挂机开关）
        MenuBarExtra {
            MenuBarPanel(settings: settings, session: session)
                .environment(\.lefuTheme, theme)
        } label: {
            // 采诗中实心图标（醒目），空闲空心。同时负责接收「显示主窗」通知。
            MenuBarLabel(session: session)
        }
        .menuBarExtraStyle(.window)
    }

    /// 主窗判定：排除菜单栏面板与系统 30pt 高的菜单栏条（同为 layer 0，但不是主窗）。
    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && $0.frame.height > 200 }
    }

    /// 显示主窗：有窗就前置（含从最小化恢复）；没有就用 openWindow 重建。
    /// 关窗会被 SwiftUI 销毁，此时 NSApp.windows 里已无主窗，单纯 makeKeyAndOrderFront 无效。
    static func revealMainWindow(using openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let win = mainWindow {
            if win.isMiniaturized { win.deminiaturize(nil) }
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    /// AppDelegate（Dock 点击 / open -a）拿不到 openWindow 环境，转成通知由常驻 label 代劳。
    static func showMain() {
        NotificationCenter.default.post(name: .lefuShowMain, object: nil)
    }

    private var colorScheme: ColorScheme? {
        switch settings.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// 基主题 + 当前封面主色派生。coverAccent 已是 Color?（Task 2 已从 NSColor 转换），
    /// 无封面/灰阶时为 nil → 回落基主题。
    ///
    /// 封面色只作装饰强调色；文本强调色 accentText 以面板底色为背景重新派生，
    /// 保证小字 / 图标前景 >= 4.5:1。填充上的前景墨色 accentContrast 按强调色亮度选取。
    private var theme: LefuTheme {
        let base: LefuTheme
        switch settings.themeMode {
        case .system:
            base = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .light: base = .light
        case .dark: base = .dark
        }
        guard let accent = session.coverAccent else { return base }

        let accentRGB = Self.srgbComponents(accent)
        // 文本强调色：达不到 4.5:1 就沿亮度修正；转换失败时回落基主题。
        let accentText: Color
        if let accentRGB, let panelRGB = Self.srgbComponents(base.panel) {
            let safe = AccentDerivation.contrastSafe(accentRGB, against: panelRGB, minRatio: 4.5)
            accentText = Color(.sRGB, red: safe.r, green: safe.g, blue: safe.b, opacity: 1)
        } else {
            accentText = base.accentText
        }

        // 填充上的前景墨色：黑墨 / 白墨按与强调色的实际对比度择优（不设固定亮度阈值）。
        let accentContrast: Color
        if let accentRGB {
            let darkInk = RGB(r: 0.08, g: 0.07, b: 0.10)
            let white = RGB(r: 1, g: 1, b: 1)
            let darkRatio = AccentDerivation.contrastRatio(accentRGB, darkInk)
            let whiteRatio = AccentDerivation.contrastRatio(accentRGB, white)
            accentContrast = darkRatio >= whiteRatio ? Color.p3(0.08, 0.07, 0.10) : .white
        } else {
            accentContrast = isDark ? Color.p3(0.08, 0.07, 0.10) : .white
        }

        return base.withAccent(accent, accentText: accentText, contrast: accentContrast)
    }

    /// 把 SwiftUI Color 转到 sRGB 分量；无法转换（如动态/非 RGB 色）时返回 nil。
    private static func srgbComponents(_ color: Color) -> RGB? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return RGB(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }

    private var isDark: Bool {
        settings.themeMode == .dark
            || (settings.themeMode == .system
                && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}

extension Notification.Name {
    /// 请求显示 / 重建主窗
    static let lefuShowMain = Notification.Name("lefu.showMain")
}

/// 常驻菜单栏图标：接收「显示主窗」通知并调用 openWindow 重建；顺便记录主窗关闭，便于日后排查。
struct MenuBarLabel: View {
    @ObservedObject var session: SessionController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: session.state == .live ? "waveform.circle.fill" : "music.note.house")
            .onReceive(NotificationCenter.default.publisher(for: .lefuShowMain)) { _ in
                LefuApp.revealMainWindow(using: openWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let win = note.object as? NSWindow, win.canBecomeMain, win.frame.height > 200 else { return }
                Diag.log("WIN 主窗关闭 frame=" + NSStringFromRect(win.frame))
            }
    }
}

// MARK: - 委托
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动时把主窗校准到 16:10 参考画幅（SwiftUI 的窗口框架记忆按视图链存取，
        // 布局一改就换键失效，容易恢复成奇怪尺寸；这里统一校准，容差 2%）
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

    // Dock 点图标 / open -a：唤回（必要时重建）主窗
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LefuApp.showMain()
        return true
    }
}
