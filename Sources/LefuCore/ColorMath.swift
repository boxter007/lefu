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
