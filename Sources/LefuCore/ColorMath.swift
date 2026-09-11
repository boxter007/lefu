import Foundation

public struct RGB: Equatable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
}

public enum AccentDerivation {
    /// 将主色钳制为可安全用作强调色的颜色；灰阶/低饱和返回 nil，由调用方回落默认色。
    public static func clamp(_ c: RGB,
                             minL: Double = 0.45, maxL: Double = 0.72,
                             minS: Double = 0.35, maxS: Double = 0.90) -> RGB? {
        let (h, s, l) = toHSL(c)
        guard s >= 0.08, l > 0.02, l < 0.98 else { return nil }
        return fromHSL(h: h, s: min(max(s, minS), maxS), l: min(max(l, minL), maxL))
    }

    public static func toHSL(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let maxV = max(c.r, c.g, c.b)
        let minV = min(c.r, c.g, c.b)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        guard d > 1e-9 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6 : 0) }
        else if maxV == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        return (h / 6, s, l)
    }

    public static func fromHSL(h: Double, s: Double, l: Double) -> RGB {
        if s <= 1e-9 { return RGB(r: l, g: l, b: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return RGB(r: hue2rgb(p, q, h + 1.0/3), g: hue2rgb(p, q, h), b: hue2rgb(p, q, h - 1.0/3))
    }

    private static func hue2rgb(_ p: Double, _ q: Double, _ t0: Double) -> Double {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0/6 { return p + (q - p) * 6 * t }
        if t < 1.0/2 { return q }
        if t < 2.0/3 { return p + (q - p) * (2.0/3 - t) * 6 }
        return p
    }
}

// MARK: - WCAG 对比度
extension RGB {
    /// WCAG 2.1 相对亮度：sRGB 线性化后按 0.2126 / 0.7152 / 0.0722 加权。
    public var relativeLuminance: Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }
}

extension AccentDerivation {
    /// WCAG 对比度（1...21）。
    public static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        let hi = max(la, lb)
        let lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// 让 rgb 在 bg 上达到 minRatio 对比度：已达标原样返回；否则沿亮度向余量更大的方向
    ///（变暗 / 变亮）调整，尽量保留色相与饱和度；两端都够不到时回落到纯黑 / 纯白。
    public static func contrastSafe(_ rgb: RGB, against bg: RGB, minRatio: Double) -> RGB {
        if contrastRatio(rgb, bg) >= minRatio { return rgb }
        let (h, s, l) = toHSL(rgb)
        let black = RGB(r: 0, g: 0, b: 0)
        let white = RGB(r: 1, g: 1, b: 1)
        // 哪一端对当前底色余量大，就先往哪端走。
        let preferDark = contrastRatio(black, bg) >= contrastRatio(white, bg)
        let directions: [Double] = preferDark ? [-1, 1] : [1, -1]
        for dir in directions {
            var delta = 0.005
            while delta <= 1.0001 {
                let nl = l + dir * delta
                if nl < 0 || nl > 1 { break }
                let candidate = fromHSL(h: h, s: s, l: nl)
                if contrastRatio(candidate, bg) >= minRatio { return candidate }
                delta += 0.005
            }
        }
        // 绝对兜底：取对比度更高的纯黑 / 纯白（且已在 [0,1] 内）。
        return contrastRatio(black, bg) >= contrastRatio(white, bg) ? black : white
    }
}
