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
        WindowGroup {
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
            // 采诗中实心图标（醒目），空闲空心
            Image(systemName: session.state == .live ? "waveform.circle.fill" : "music.note.house")
        }
        .menuBarExtraStyle(.window)
    }

    /// 关窗后从菜单栏唤回主窗
    static func showMain() {
        NSApp.activate(ignoringOtherApps: true)
        let win = NSApp.windows.first { $0.canBecomeMain }
        win?.makeKeyAndOrderFront(nil)
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

// MARK: - 委托
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动时把主窗校准到 16:10 参考画幅（SwiftUI 的窗口框架记忆按视图链存取，
        // 布局一改就换键失效，容易恢复成奇怪尺寸；这里统一校准，容差 2%）
        DispatchQueue.main.async {
            guard let win = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
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
}
