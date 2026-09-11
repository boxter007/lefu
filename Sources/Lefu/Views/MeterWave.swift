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
//
// 观感沿用最初版本：底对齐、accent→live 竖向渐变、每根柱子高度有起伏、
// 随电平一波波亮起。美化点：起音快/落音慢的平滑包络、柔和辉光、
// 闪烁由硬切改为渐变，柱子更顺滑、更有余韵。

final class MeterWaveView: NSView {
    private var bars: [CAGradientLayer] = []
    private var cancellable: AnyCancellable?
    private weak var meter: LevelMeter?

    private let barCount = 48
    private let spacing: CGFloat = 3
    /// 平滑包络：起音快、落音慢，柱子像真实音频一样滑动而不是硬跳
    private var smoothLevel: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 视图坐标系原点固定在左下，柱子的 y 即「距底部的距离」，向上生长。
        layer?.isGeometryFlipped = false
        for _ in 0..<barCount {
            let g = CAGradientLayer()
            // 层坐标原点在左下，(0.5,0) 即底部 ⇒ accent 在下、live 在上。
            g.startPoint = CGPoint(x: 0.5, y: 0.0)
            g.endPoint = CGPoint(x: 0.5, y: 1.0)
            // 柔光：让柱体从氛围背景里浮起来
            g.shadowOpacity = 0.22
            g.shadowRadius = 3
            g.shadowOffset = .zero
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
        for g in bars {
            g.colors = colors
            g.shadowColor = live.cgColor
        }
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

        // 平滑包络：起音 0.55、落音 0.14，保留律动又不生硬
        let target = CGFloat(min(max(level, 0), 1))
        smoothLevel += (target - smoothLevel) * (target > smoothLevel ? 0.55 : 0.14)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let totalSpacing = spacing * CGFloat(bars.count - 1)
        let bw = max(1, (bounds.width - totalSpacing) / CGFloat(bars.count))

        // 先算各柱高度，再取最高者：整簇在竖直方向居中、各柱底对齐，向上生长。
        var heights: [CGFloat] = []
        heights.reserveCapacity(bars.count)
        for i in 0..<bars.count {
            let base: CGFloat = 6
            let noise = CGFloat((i * 37) % 23) / 23 * 10
            let live = smoothLevel * 26
            heights.append(min(bounds.height, base + noise + live * (i % 3 == 0 ? 1 : 0.6)))
        }
        let hMax = heights.max() ?? 0
        let bottomInset = max(0, (bounds.height - hMax) / 2)

        for (i, g) in bars.enumerated() {
            let h = heights[i]
            g.frame = CGRect(x: CGFloat(i) * (bw + spacing),
                             y: bottomInset,
                             width: bw,
                             height: h)
            g.cornerRadius = bw / 2
            // 一波波亮起：把原来的二值闪烁改成随扫过位置的平滑渐变
            let phase = (smoothLevel * 12) - CGFloat(i % 12)
            let twinkle = min(max(phase, 0), 1)
            g.opacity = Float(0.28 + 0.72 * twinkle)
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
