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
    private var bars: [CALayer] = []
    private var caps: [CALayer] = []
    private var peaks: [CGFloat] = []
    private var cancellable: AnyCancellable?
    private weak var meter: LevelMeter?

    private let barCount = 48
    private let spacing: CGFloat = 3
    /// 上下留白：波形永远不顶到视图边缘被裁
    private let barInset: CGFloat = 3
    /// 静音也保留一点高度，安静段仍有呼吸感
    private let floorFraction: CGFloat = 0.06
    /// 峰值包络每拍衰减系数（越大保留越久），0.90 给出余韵
    private let peakDecay: CGFloat = 0.90

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 视图坐标系原点固定在左下，柱子 y 即「距底部的距离」。
        layer?.isGeometryFlipped = false
        for _ in 0..<barCount {
            let b = CALayer()
            b.cornerRadius = 2
            // 柔光：让柱体从氛围背景里浮起来，颜色在 applyPalette 里按位插值
            b.shadowOpacity = 0.3
            b.shadowRadius = 2
            b.shadowOffset = .zero
            layer?.addSublayer(b)
            bars.append(b)

            // 峰值帽：一条细亮高光，骑在峰值高度边缘
            let c = CALayer()
            c.cornerRadius = 1
            c.shadowOpacity = 0.35
            c.shadowRadius = 2
            c.shadowOffset = .zero
            layer?.addSublayer(c)
            caps.append(c)
        }
        peaks = Array(repeating: 0, count: barCount)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func bind(meter: LevelMeter, accent: NSColor, live: NSColor) {
        // 主题换色时也要刷新（配色跟柱位绑定，不依赖电平订阅）
        applyPalette(accent: accent, live: live)
        guard self.meter !== meter else { return }
        self.meter = meter
        cancellable = meter.$history
            .receive(on: RunLoop.main)
            .sink { [weak self] history in self?.render(history: history) }
    }

    /// 按柱位在 accent → live 之间插值：整簇从左到右走完色相。
    /// 峰值帽取同色再向白提亮，形成细亮高光。
    private func applyPalette(accent: NSColor, live: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let n = bars.count
        for i in 0..<n {
            let t = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0
            let c = accent.blended(withFraction: t, of: live) ?? accent
            bars[i].backgroundColor = c.cgColor
            bars[i].shadowColor = c.cgColor
            let capColor = c.blended(withFraction: 0.55, of: .white) ?? .white
            caps[i].backgroundColor = capColor.cgColor
            caps[i].shadowColor = capColor.cgColor
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        render(history: meter?.history ?? Array(repeating: 0, count: barCount))
    }

    private func render(history: [Float]) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let n = bars.count
        let totalSpacing = spacing * CGFloat(n - 1)
        let bw = max(1, (bounds.width - totalSpacing) / CGFloat(n))
        let midY = bounds.height / 2
        let maxH = max(1, bounds.height - barInset * 2)
        let capH: CGFloat = 2
        let floor = maxH * floorFraction

        for i in 0..<n {
            let raw = i < history.count ? CGFloat(history[i]) : 0
            let v = min(max(raw, 0), 1)
            // 真实 history 驱动高度 + 小地板；镜像：从中线向上下各伸 h/2
            let h = maxH * (floorFraction + v * (1 - floorFraction))
            let x = CGFloat(i) * (bw + spacing)
            bars[i].frame = CGRect(x: x, y: midY - h / 2, width: bw, height: h)
            bars[i].cornerRadius = bw / 2

            // 峰值包络：跳到当前高度，之后每拍缓慢衰减（带地板）
            let p = max(h, max(peaks[i] * peakDecay, floor))
            peaks[i] = p
            caps[i].frame = CGRect(x: x, y: midY - p / 2 - capH / 2, width: bw, height: capH)
            caps[i].cornerRadius = capH / 2
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
