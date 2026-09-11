import SwiftUI
import AppKit
import QuartzCore
import Combine

// MARK: - 电平波形（CA 层直驱）
//
// 为什么不用纯 SwiftUI：
// 电平每秒刷新 20+ 次。只要波形是 SwiftUI 视图，每次刷新都会把视图图标脏，
// 触发 RootGeometry 全树重算（实测每次约 3ms）。这里让 NSView 自己订阅电平表、
// 直接改 CALayer 的 frame —— SwiftUI 视图图完全不知道电平在跳，
// 于是整块波形对上层是「静止」的，只有渲染服务端在动。

final class MeterWaveView: NSView {
    private var bars: [CAGradientLayer] = []
    private var cancellable: AnyCancellable?
    private weak var meter: LevelMeter?

    private let barCount = 48
    private let spacing: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for _ in 0..<barCount {
            let g = CAGradientLayer()
            g.startPoint = CGPoint(x: 0.5, y: 1.0)   // 自下而上
            g.endPoint = CGPoint(x: 0.5, y: 0.0)
            layer?.addSublayer(g)
            bars.append(g)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func bind(meter: LevelMeter, accent: NSColor, live: NSColor) {
        guard self.meter !== meter else { return }
        self.meter = meter
        let colors = [accent.cgColor, live.cgColor]
        for g in bars { g.colors = colors }
        cancellable = meter.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] lv in self?.render(level: lv) }
    }

    override func layout() {
        super.layout()
        render(level: meter?.level ?? 0)
    }

    private func render(level: Float) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let totalSpacing = spacing * CGFloat(bars.count - 1)
        let bw = max(1, (bounds.width - totalSpacing) / CGFloat(bars.count))
        for (i, g) in bars.enumerated() {
            let base: CGFloat = 6
            let noise = CGFloat((i * 37) % 23) / 23 * 10
            let live = CGFloat(level) * 26
            let h = min(bounds.height, base + noise + live * (i % 3 == 0 ? 1 : 0.6))
            g.frame = CGRect(x: CGFloat(i) * (bw + spacing),
                             y: bounds.height - h,
                             width: bw,
                             height: h)
            g.cornerRadius = bw / 2
            g.opacity = level > Float(i % 12) / 12 ? 1.0 : 0.28
        }
        CATransaction.commit()
    }
}

/// 波形容器：**不订阅**电平表（关键），订阅发生在内部 NSView 上
struct LevelWave: View {
    let meter: LevelMeter
    let theme: LefuTheme

    var body: some View {
        MeterWave(meter: meter, accent: theme.accent, live: theme.live)
            .frame(height: 44)
    }
}

struct MeterWave: NSViewRepresentable {
    let meter: LevelMeter
    let accent: Color
    let live: Color

    func makeNSView(context: Context) -> MeterWaveView { MeterWaveView() }

    func updateNSView(_ v: MeterWaveView, context: Context) {
        v.bind(meter: meter, accent: NSColor(accent), live: NSColor(live))
    }
}
