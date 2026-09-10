import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 乐府 App 图标生成器：1024×1024，Big Sur 风格
// 主题：一段录音波形被切割线裁开，右半下沉错位 —— "收卷裁曲"
// 用法: xcrun swiftc scripts/make_icon.swift -o /tmp/make_icon && /tmp/make_icon <输出.png>

let size = 1024.0
let canvas = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                       bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// MARK: - 调色
func p3(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            components: [r, g, b, a])!
}
let plumDeep = p3(0.13, 0.05, 0.16)     // 深夜紫
let roseMid  = p3(0.72, 0.16, 0.36)     // 玫红（对应 accent）
let amberHi  = p3(0.96, 0.42, 0.16)     // 暖橙（对应 live / 切割线）

// MARK: 画布
canvas.setFillColor(p3(0, 0, 0, 0))
canvas.fill(CGRect(x: 0, y: 0, width: size, height: size))

// 圆角矩形（Big Sur 模板：1024 画布，824 内容，圆角 185）
let inset = 100.0
let contentRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner = 185.0
let squircle = CGPath(roundedRect: contentRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

// 背景：对角渐变 夜紫 → 玫红 → 暖橙
canvas.saveGState()
canvas.addPath(squircle)
canvas.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                    colors: [plumDeep, roseMid, amberHi] as CFArray,
                    locations: [0.0, 0.55, 1.0])!
canvas.drawLinearGradient(bg, start: CGPoint(x: inset, y: size - inset),
                          end: CGPoint(x: size - inset, y: inset), options: [])

// 左上柔光
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                      colors: [CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)] as CFArray,
                      locations: [0.0, 1.0])!
canvas.drawRadialGradient(glow, startCenter: CGPoint(x: 320, y: size - 320), startRadius: 0,
                          endCenter: CGPoint(x: 320, y: size - 320), endRadius: 460, options: [])
// 底部暗角
let vignette = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                          colors: [CGColor(gray: 0, alpha: 0.35), CGColor(gray: 0, alpha: 0)] as CFArray,
                          locations: [0.0, 1.0])!
canvas.drawRadialGradient(vignette,
                          startCenter: CGPoint(x: size / 2, y: -140), startRadius: 120,
                          endCenter: CGPoint(x: size / 2, y: -140), endRadius: 900, options: [])
canvas.restoreGState()

// 描边：外圈 1px 暗色 + 内圈 1px 亮色（玻璃质感）
canvas.addPath(squircle)
canvas.setStrokeColor(CGColor(gray: 0, alpha: 0.22))
canvas.setLineWidth(3)
canvas.strokePath()
let inner = contentRect.insetBy(dx: 4, dy: 4)
canvas.addPath(CGPath(roundedRect: inner, cornerWidth: corner - 4, cornerHeight: corner - 4, transform: nil))
canvas.setStrokeColor(CGColor(gray: 1, alpha: 0.30))
canvas.setLineWidth(2)
canvas.strokePath()

// MARK: 主视觉：录音波形被切割线裁开，右半下沉错位
canvas.saveGState()
canvas.setShadow(offset: CGSize(width: 0, height: 6), blur: 22, color: CGColor(gray: 0, alpha: 0.30))

let white = CGColor(gray: 1, alpha: 1)
let barW: CGFloat = 38, barGap: CGFloat = 22
let slit: CGFloat = 52                       // 切口宽度
let leftHeights:  [CGFloat] = [180, 320, 460, 340, 200]
let rightHeights: [CGFloat] = [200, 340, 460, 320, 180]
let centerY: CGFloat = 545                    // 波形中轴
let dropY: CGFloat = 34                       // 右半下沉量
let cutX = size / 2                           // 切割线所在 x

func groupWidth(_ hs: [CGFloat]) -> CGFloat {
    CGFloat(hs.count) * barW + CGFloat(hs.count - 1) * barGap
}
let totalW = groupWidth(leftHeights) + slit + groupWidth(rightHeights)
var x0 = (CGFloat(size) - totalW) / 2

func drawBars(_ hs: [CGFloat], startX: CGFloat, dy: CGFloat, alpha: CGFloat) {
    var x = startX
    for h in hs {
        let rect = CGRect(x: x, y: centerY + dy - h / 2, width: barW, height: h)
        let r = CGPath(roundedRect: rect, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
        canvas.addPath(r)
        canvas.setFillColor(white.copy(alpha: alpha)!)
        canvas.fillPath()
        x += barW + barGap
    }
}
drawBars(leftHeights, startX: x0, dy: -dropY / 2, alpha: 0.96)
drawBars(rightHeights, startX: x0 + groupWidth(leftHeights) + slit, dy: dropY, alpha: 0.92)

// 切割线：暖橙发光竖线 + 顶端游标三角（时间游标，正在下刀）
canvas.setShadow(offset: CGSize(width: 0, height: 0), blur: 26, color: amberHi.copy(alpha: 0.85)!)
let lineW: CGFloat = 9
let lineTop: CGFloat = 845, lineBottom: CGFloat = 205
let lineRect = CGRect(x: cutX - lineW / 2, y: lineBottom, width: lineW, height: lineTop - lineBottom)
canvas.addPath(CGPath(roundedRect: lineRect, cornerWidth: lineW / 2, cornerHeight: lineW / 2, transform: nil))
canvas.setFillColor(white)
canvas.fillPath()

// 游标三角（倒三角压在线顶，尖朝下"下刀"）
let tri = CGMutablePath()
tri.move(to: CGPoint(x: cutX, y: lineTop + 2))
tri.addLine(to: CGPoint(x: cutX - 30, y: lineTop + 40))
tri.addLine(to: CGPoint(x: cutX + 30, y: lineTop + 40))
tri.closeSubpath()
canvas.addPath(tri)
canvas.setFillColor(white)
canvas.fillPath()

// 底端游标（尖朝上，与顶端上下夹住裁切区间）
let tri2 = CGMutablePath()
tri2.move(to: CGPoint(x: cutX, y: lineBottom - 2))
tri2.addLine(to: CGPoint(x: cutX - 30, y: lineBottom - 40))
tri2.addLine(to: CGPoint(x: cutX + 30, y: lineBottom - 40))
tri2.closeSubpath()
canvas.addPath(tri2)
canvas.setFillColor(white)
canvas.fillPath()

// 切口两侧细光缝（暗示"刚裁开"）
canvas.setShadow(offset: .zero, blur: 0, color: nil)
canvas.restoreGState()

// MARK: 输出
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                           UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, canvas.makeImage()!, [:] as CFDictionary)
CGImageDestinationFinalize(dest)
print("icon → \(out)")
