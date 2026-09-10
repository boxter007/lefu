import SwiftUI

// MARK: - 主题模式
enum ThemeMode: String, CaseIterable {
    case system, light, dark
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

// MARK: - 字体阶梯（对齐 Apple HIG macOS：body 13 / subhead 11 / title2 17 / largeTitle 26）
// 大字与数字走 SF Rounded（圆润 UI），小字用默认 SF Pro
enum LefuFont {
    case largeTitle   // 26 rounded medium — 歌名
    case title2       // 17 semibold — 状态大标题
    case headline     // 13 semibold — 区块标题/按钮强调
    case body         // 13 regular — 正文
    case callout      // 12 regular — 次要描述
    case subheadline  // 11 regular — 辅助说明
    case mono         // 13 rounded monospaced digit — 计时/进度
}

extension Font {
    static func lefu(_ s: LefuFont) -> Font {
        switch s {
        case .largeTitle: return .system(size: 26, weight: .medium, design: .rounded)
        case .title2: return .system(size: 17, weight: .semibold, design: .rounded)
        case .headline: return .system(size: 13, weight: .semibold)
        case .body: return .system(size: 13)
        case .callout: return .system(size: 12)
        case .subheadline: return .system(size: 11)
        case .mono: return .system(size: 13, weight: .medium, design: .rounded).monospacedDigit()
        }
    }
}

// MARK: - 主题 Token（P3 广色域 + 双主题）
struct LefuTheme {
    let bg: Color
    let panel: Color
    let panel2: Color
    let rail: Color
    let border: Color
    let border2: Color
    let text: Color
    let text2: Color
    let text3: Color
    let accent: Color
    let accentContrast: Color
    let live: Color
    let ok: Color
    let skip: Color
    let shadow: Color
}

extension Color {
    static func p3(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.displayP3, red: r, green: g, blue: b, opacity: 1)
    }
}

extension LefuTheme {
    static let dark = LefuTheme(
        bg: Color.p3(0.075, 0.072, 0.096),
        panel: Color.p3(0.115, 0.108, 0.146),
        panel2: Color.p3(0.152, 0.146, 0.187),
        rail: Color.p3(0.095, 0.090, 0.122),
        border: Color.p3(0.165, 0.165, 0.20).opacity(0.9),
        border2: Color.p3(0.23, 0.23, 0.27),
        text: Color.p3(0.95, 0.94, 0.97),
        text2: Color.p3(0.63, 0.62, 0.67),
        text3: Color.p3(0.44, 0.40, 0.48),
        accent: Color.p3(1.00, 0.62, 0.72),      // P3 粉，更透亮
        accentContrast: Color.p3(0.08, 0.07, 0.10),
        live: Color.p3(1.00, 0.50, 0.18),        // P3 橙，live 专用
        ok: Color.p3(0.24, 0.80, 0.36),
        skip: Color.p3(0.44, 0.44, 0.48),
        shadow: Color.black.opacity(0.5)
    )
    static let light = LefuTheme(
        bg: Color.p3(0.985, 0.980, 0.990),
        panel: .white,
        panel2: Color.p3(0.935, 0.915, 0.950),
        rail: Color.p3(0.960, 0.952, 0.970),
        border: Color.black.opacity(0.07),
        border2: Color.black.opacity(0.13),
        text: Color.p3(0.13, 0.115, 0.17),
        text2: Color.p3(0.52, 0.49, 0.57),
        text3: Color.p3(0.70, 0.67, 0.74),
        accent: Color.p3(0.86, 0.28, 0.47),      // P3 玫红
        accentContrast: .white,
        live: Color.p3(0.90, 0.33, 0.12),
        ok: Color.p3(0.03, 0.50, 0.35),
        skip: Color.p3(0.66, 0.64, 0.69),
        shadow: Color(red: 0.2, green: 0.12, blue: 0.25).opacity(0.10)
    )
}

// MARK: - 环境注入
private struct LefuThemeKey: EnvironmentKey {
    static let defaultValue: LefuTheme = .dark
}
extension EnvironmentValues {
    var lefuTheme: LefuTheme {
        get { self[LefuThemeKey.self] }
        set { self[LefuThemeKey.self] = newValue }
    }
}

// MARK: - 卡片修饰（统一阴影+圆角+描边）
struct LefuCard: ViewModifier {
    var theme: LefuTheme
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.panel))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(theme.border, lineWidth: 0.5))
            .shadow(color: theme.shadow, radius: 4, x: 0, y: 2)
    }
}
extension View {
    func lefuCard(_ theme: LefuTheme, radius: CGFloat = 10) -> some View {
        modifier(LefuCard(theme: theme, radius: radius))
    }
}
