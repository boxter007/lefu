import SwiftUI
import AppKit
import CoreImage
import QuartzCore

// MARK: - 模糊封面（后台生成 + 按 key 缓存）
//
// 高斯模糊可能耗时数十毫秒，绝不能同步跑在主线程，否则每次切歌都掉帧。
// 这里只在主线程取 CGImage（AppKit 对象不跨线程），模糊放串行后台队列，
// 结果按 key 缓存，回到主线程交付；调用方（AmbientBackground）用 lastKey 做陈旧守卫。
enum BlurredCover {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static let queue = DispatchQueue(label: "com.lefu.ambient.blur", qos: .userInitiated)
    private static let lock = NSLock()
    private static var cache: [String: CGImage] = [:]
    private static var order: [String] = []
    private static let cacheLimit = 16
    private static let maxDimension: CGFloat = 1024   // 超大封面先降采样，控制模糊成本
    private static let sigma: CGFloat = 40

    static func cached(_ key: String) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        guard let hit = cache[key] else { return nil }
        // 命中时刷新 LRU 新近度（否则退化成 FIFO）
        order.removeAll { $0 == key }
        order.append(key)
        return hit
    }

    /// cgImage 为 nil（无封面）时不 blur，直接回主线程交付 nil。
    static func render(cgImage: CGImage?, key: String, completion: @escaping (CGImage?) -> Void) {
        guard let cgImage else { completion(nil); return }
        queue.async {
            let ci = CIImage(cgImage: cgImage)
            let longest = max(ci.extent.width, ci.extent.height)
            let scale = longest > maxDimension ? maxDimension / longest : 1
            let scaled = scale < 1 ? ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : ci
            let blurred = scaled.applyingGaussianBlur(sigma: sigma).cropped(to: scaled.extent)
            let out = context.createCGImage(blurred, from: scaled.extent)
            if let out {
                lock.lock()
                cache[key] = out
                order.removeAll { $0 == key }
                order.append(key)
                while order.count > cacheLimit {
                    cache[order.removeFirst()] = nil
                }
                lock.unlock()
            }
            DispatchQueue.main.async { completion(out) }
        }
    }
}

// MARK: - 氛围背景视图（CA 层直驱）
final class AmbientView: NSView {
    private let aLayer = CALayer()
    private let bLayer = CALayer()
    private let scrim = CAGradientLayer()
    private var showingA = true
    private var scrimIsDark = true
    /// 当前已请求的封面 key（陈旧守卫用）
    var lastKey = ""
    /// 当前已应用的封面对象：同一 key 上封面晚到时也要触发一次
    var lastImage: NSImage?
    /// 是否已成功渲染过一帧：首帧不淡入，之后切歌 0.6s 交叉淡入
    var hasRendered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        for l in [aLayer, bLayer] {
            l.contentsGravity = .resizeAspectFill
            l.masksToBounds = true
            l.opacity = 0
            layer?.addSublayer(l)
        }
        aLayer.opacity = 1

        // macOS 非翻转 NSView 的层坐标 y 向上：y=1 是视觉顶部。
        // 顶部用较浅遮罩（保留氛围），底部压得更沉（视觉落定）。
        scrim.startPoint = CGPoint(x: 0.5, y: 1)
        scrim.endPoint = CGPoint(x: 0.5, y: 0)
        scrim.locations = [0, 1]
        applyScrimColors(isDark: true)
        layer?.addSublayer(scrim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 遮罩必须跟随主题：深色主题用黑压暗（浅色正文），浅色主题用白提亮（深色正文）。
    /// 数值按最坏情况（纯白/纯黑封面）保正文 >= 4.5:1、辅助 >= 3:1，详见报告。
    private func applyScrimColors(isDark: Bool) {
        if isDark {
            scrim.colors = [NSColor.black.withAlphaComponent(0.72).cgColor,
                            NSColor.black.withAlphaComponent(0.88).cgColor]
        } else {
            // 浅色主题正文/辅助都是深色字，遮罩要更实；数值见 task-3-report 对比度表
            scrim.colors = [NSColor.white.withAlphaComponent(0.80).cgColor,
                            NSColor.white.withAlphaComponent(0.92).cgColor]
        }
    }

    func setScrim(isDark: Bool) {
        guard scrimIsDark != isDark else { return }
        scrimIsDark = isDark
        CATransaction.begin(); CATransaction.setDisableActions(true)
        applyScrimColors(isDark: isDark)
        CATransaction.commit()
    }

    func setCover(_ cg: CGImage?) {
        let incoming = showingA ? bLayer : aLayer
        let outgoing = showingA ? aLayer : bLayer
        incoming.contents = cg
        CATransaction.begin()
        CATransaction.setAnimationDuration(hasRendered ? 0.6 : 0)
        incoming.opacity = cg == nil ? 0 : 1
        outgoing.opacity = 0
        CATransaction.commit()
        showingA.toggle()
    }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        aLayer.frame = bounds; bLayer.frame = bounds; scrim.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - SwiftUI 桥接
struct AmbientBackground: NSViewRepresentable {
    let image: NSImage?
    let key: String
    let isDark: Bool

    func makeNSView(context: Context) -> AmbientView { AmbientView() }

    func updateNSView(_ v: AmbientView, context: Context) {
        // 主题可能变化，遮罩同步（不触发 blur）
        v.setScrim(isDark: isDark)

        // key 或封面对象变化才入队，避免每次 SwiftUI 重算都重新模糊；
        // 封面可能在同 key 上晚到（元信息纠正），只比对 key 会把这次更新吞掉。
        let keyChanged = v.lastKey != key
        let imageChanged = v.lastImage !== image
        guard keyChanged || imageChanged else { return }
        v.lastKey = key
        v.lastImage = image

        guard !key.isEmpty, image != nil else {
            // 无曲目 / 无封面：淡出到纯色底（th.bg）
            v.setCover(nil)
            v.hasRendered = true
            return
        }
        if let cached = BlurredCover.cached(key) {
            v.setCover(cached)
            v.hasRendered = true
            return
        }
        let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        BlurredCover.render(cgImage: cg, key: key) { [weak v] out in
            guard let v, v.lastKey == key else { return }   // 陈旧 key 丢弃
            v.setCover(out)
            v.hasRendered = true
        }
    }
}
