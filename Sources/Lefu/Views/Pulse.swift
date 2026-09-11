import SwiftUI
import AppKit
import QuartzCore

// MARK: - CA 层驱动的呼吸/脉冲动效
//
// 为什么不用 SwiftUI 的 `.repeatForever`：
// SwiftUI 的持续性动画每帧（60Hz）都会把视图图标脏 → `NSRunLoop.flushObservers`
// → AttributeGraph 更新 → 根布局 `RootGeometry.sizeThatFits` 重算整棵视图树。
// 采录中同时有「顶栏录音圆点」「会话行描边」两处在呼吸（待机页还有光环），
// 相当于每秒 60 次全树布局 —— 实测主线程约 25% 耗在这条路径上（2026-09-11 采样确认）。
//
// 换成 CABasicAnimation 后，动画完全跑在渲染服务端；SwiftUI 视图图只按真实业务数据刷新
// （1Hz 计时 / 会话事件 / 电平），空闲时几乎零成本。

/// 脉冲展示层：一个不吃鼠标事件的透明 NSView，内部用 CAShapeLayer / CAGradientLayer 做动画
final class PulseLayerView: NSView {
    enum Shape: Equatable {
        case circle
        case roundedRect(CGFloat)
        case radialHalo
    }

    private let shapeLayer = CAShapeLayer()
    private let gradientLayer = CAGradientLayer()
    private var shape: Shape = .circle
    private var minOpacity: Double = 0.15
    private var maxOpacity: Double = 1.0
    private var duration: Double = 1.1
    private var scaleRange: (CGFloat, CGFloat)?
    private var configKey = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradientLayer.type = .radial
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = nil
        layer?.addSublayer(gradientLayer)
        layer?.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 完全透明、不拦截鼠标（行上的「点击开 Finder」必须照常可用）
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(shape: Shape,
                   color: NSColor,
                   filled: Bool,
                   minOpacity: Double,
                   maxOpacity: Double,
                   duration: Double,
                   lineWidth: CGFloat = 1,
                   scaleFrom: CGFloat? = nil,
                   scaleTo: CGFloat? = nil) {
        let key = "\(shape)|\(color.description)|\(filled)|\(minOpacity)|\(maxOpacity)|\(duration)|\(lineWidth)|\(scaleFrom ?? -1)|\(scaleTo ?? -1)"
        guard key != configKey else { return }   // 父视图重算时不要重启动画（重启会闪一下）
        configKey = key

        self.shape = shape
        self.minOpacity = minOpacity
        self.maxOpacity = maxOpacity
        self.duration = duration
        self.scaleRange = (scaleFrom != nil && scaleTo != nil) ? (scaleFrom!, scaleTo!) : nil

        switch shape {
        case .radialHalo:
            gradientLayer.isHidden = false
            shapeLayer.isHidden = true
            gradientLayer.colors = [color.withAlphaComponent(0.30).cgColor,
                                    color.withAlphaComponent(0.0).cgColor]
        case .circle, .roundedRect:
            gradientLayer.isHidden = true
            shapeLayer.isHidden = false
            if filled {
                shapeLayer.fillColor = color.cgColor
                shapeLayer.strokeColor = nil
            } else {
                shapeLayer.fillColor = nil
                shapeLayer.strokeColor = color.cgColor
                shapeLayer.lineWidth = lineWidth
            }
        }
        startAnimations()
        needsLayout = true
    }

    private func startAnimations() {
        let target: CALayer = (shape == .radialHalo) ? gradientLayer : shapeLayer
        target.removeAnimation(forKey: "breathe")
        target.removeAnimation(forKey: "pulseScale")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = minOpacity
        fade.toValue = maxOpacity
        fade.duration = duration
        fade.autoreverses = true
        fade.repeatCount = .greatestFiniteMagnitude
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        target.add(fade, forKey: "breathe")

        if let s = scaleRange {
            let sc = CABasicAnimation(keyPath: "transform.scale")
            sc.fromValue = s.0
            sc.toValue = s.1
            sc.duration = duration
            sc.autoreverses = true
            sc.repeatCount = .greatestFiniteMagnitude
            sc.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            target.add(sc, forKey: "pulseScale")
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // 布局引起的 frame/path 变化不要产生隐式动画
        gradientLayer.frame = bounds
        shapeLayer.frame = bounds
        switch shape {
        case .circle:
            shapeLayer.path = CGPath(ellipseIn: bounds, transform: nil)
        case .roundedRect(let r):
            shapeLayer.path = CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        case .radialHalo:
            break
        }
        CATransaction.commit()
    }
}

// MARK: - SwiftUI 封装

/// 实心圆点呼吸（顶栏「录音中」圆点）
struct PulseDot: NSViewRepresentable {
    let color: Color
    var minOpacity: Double = 0.3
    var duration: Double = 1.0

    func makeNSView(context: Context) -> PulseLayerView { PulseLayerView() }

    func updateNSView(_ v: PulseLayerView, context: Context) {
        v.configure(shape: .circle, color: NSColor(color), filled: true,
                    minOpacity: minOpacity, maxOpacity: 1.0, duration: duration)
    }
}

/// 圆角描边呼吸（采录中行的薄框）
struct PulseBorder: NSViewRepresentable {
    let color: Color
    var cornerRadius: CGFloat = 12
    var minOpacity: Double = 0.12
    var maxOpacity: Double = 0.75

    func makeNSView(context: Context) -> PulseLayerView { PulseLayerView() }

    func updateNSView(_ v: PulseLayerView, context: Context) {
        v.configure(shape: .roundedRect(cornerRadius), color: NSColor(color), filled: false,
                    minOpacity: minOpacity, maxOpacity: maxOpacity, duration: 1.1)
    }
}

/// 径向光晕呼吸（待机页「开始采诗」按钮的呼吸光环）
struct PulseHalo: NSViewRepresentable {
    let color: Color

    func makeNSView(context: Context) -> PulseLayerView { PulseLayerView() }

    func updateNSView(_ v: PulseLayerView, context: Context) {
        v.configure(shape: .radialHalo, color: NSColor(color), filled: false,
                    minOpacity: 0.55, maxOpacity: 1.0, duration: 2.4,
                    scaleFrom: 0.92, scaleTo: 1.10)
    }
}

/// 圆环缩放呼吸（待机页主按钮的外圈描边）
struct PulseRing: NSViewRepresentable {
    let color: Color
    var lineWidth: CGFloat = 2
    var scaleFrom: CGFloat = 0.98
    var scaleTo: CGFloat = 1.04

    func makeNSView(context: Context) -> PulseLayerView { PulseLayerView() }

    func updateNSView(_ v: PulseLayerView, context: Context) {
        v.configure(shape: .circle, color: NSColor(color), filled: false,
                    minOpacity: 1.0, maxOpacity: 1.0, duration: 2.4,
                    lineWidth: lineWidth, scaleFrom: scaleFrom, scaleTo: scaleTo)
    }
}
