import SwiftUI
import AppKit
import LefuCore

// MARK: - 主题派生（主窗与菜单栏面板共用）
//
// 为什么单独抽出来：乐府有两个独立的 SwiftUI 宿主——
//   · 主窗（WindowGroup）
//   · 菜单栏面板（AppKit 的 NSPopover + NSHostingController，见 MenuBarBridge）
// 后者拿不到主窗的 `.environment(\.lefuTheme, ...)`，如果各写一份派生逻辑，
// 很容易出现「面板少了封面强调色」这种不一致（早期版本就踩过）。
// 这里集中一处，两边都调它，保证视觉完全一致。
//
// 标注 @MainActor：SessionController 是主线程隔离的（读 coverAccent 会受并发检查），
// 两个调用点（App.body 与 menu bar 安装）本身也都在主线程。

@MainActor
enum LefuThemeFactory {

    /// 按设置与当前封面主色派生主题。
    ///
    /// 封面色只作装饰强调色：
    /// - `accentText`：文本/图标色，以面板底色为背景重新派生，保证对比度 >= 4.5:1
    /// - `accentContrast`：填充上的前景墨色，黑墨/白墨按与强调色的实际对比度择优
    /// 无封面或灰阶时 `coverAccent` 为 nil → 回落基主题。
    static func make(settings: AppSettings, session: SessionController) -> LefuTheme {
        let base = baseTheme(for: settings)

        guard let accent = session.coverAccent else { return base }
        let accentRGB = srgbComponents(accent)

        let accentText: Color
        if let accentRGB, let panelRGB = srgbComponents(base.panel) {
            let safe = AccentDerivation.contrastSafe(accentRGB, against: panelRGB, minRatio: 4.5)
            accentText = Color(.sRGB, red: safe.r, green: safe.g, blue: safe.b, opacity: 1)
        } else {
            accentText = base.accentText
        }

        let accentContrast: Color
        if let accentRGB {
            let darkInk = RGB(r: 0.08, g: 0.07, b: 0.10)
            let white = RGB(r: 1, g: 1, b: 1)
            let darkRatio = AccentDerivation.contrastRatio(accentRGB, darkInk)
            let whiteRatio = AccentDerivation.contrastRatio(accentRGB, white)
            accentContrast = darkRatio >= whiteRatio ? Color.p3(0.08, 0.07, 0.10) : .white
        } else {
            accentContrast = isDark(settings) ? Color.p3(0.08, 0.07, 0.10) : .white
        }

        return base.withAccent(accent, accentText: accentText, contrast: accentContrast)
    }

    /// SwiftUI 的 preferredColorScheme：system 交还系统决定
    static func colorScheme(for settings: AppSettings) -> ColorScheme? {
        switch settings.themeMode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    // MARK: - 内部

    static func isDark(_ settings: AppSettings) -> Bool {
        switch settings.themeMode {
        case .dark:   return true
        case .light:  return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    private static func baseTheme(for settings: AppSettings) -> LefuTheme {
        isDark(settings) ? .dark : .light
    }

    /// 把 SwiftUI Color 转到 sRGB 分量；无法转换（如动态/非 RGB 色）时返回 nil。
    private static func srgbComponents(_ color: Color) -> RGB? {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return RGB(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }
}
