import SwiftUI

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

    private var theme: LefuTheme {
        switch settings.themeMode {
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        }
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
