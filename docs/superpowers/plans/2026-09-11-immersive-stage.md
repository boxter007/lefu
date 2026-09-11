# 沉浸式采诗台 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 把乐府「采诗」从功能页变成由封面驱动的沉浸式舞台，并在不牺牲既有性能的前提下兑现 #14–#18。

**Architecture:** 纯逻辑（颜色数学、歌词文档）抽到新的无 UI 库 LefuCore 以便测试；视觉层用 Core Animation 直驱的 NSViewRepresentable（氛围背景、真实波形），避免 SwiftUI 全树重绘；主题在运行时按封面主色派生。

**Tech Stack:** Swift 5.9 · SwiftUI · AppKit · Core Image · Core Animation · UserNotifications · SwiftPM（无第三方依赖）

**Spec:** docs/superpowers/specs/2026-09-11-immersive-stage-design.md

## Global Constraints

- 平台 macOS 13+；swiftLanguageVersions 保持 [.v5]（GCD + MainActor 混用）。
- 不新增任何第三方依赖。
- 所有持续性动画一律 Core Animation 层驱动，禁止 SwiftUI repeatForever（否则退回 v1.0.1 性能病）。
- accent 不单独承载小字；正文对比度 ≥ 4.5:1，辅助文字 ≥ 3:1；深浅两主题都要过。
- 输出目录、命名、编码格式策略不变。
- 纯逻辑放进 LefuCore；App 只做平台调用与视图。

## File Structure

- Package.swift — 新增 LefuCore 库目标与 LefuCoreTests，主目标依赖 LefuCore。
- Sources/LefuCore/ColorMath.swift — RGB/HSL 与强调色钳制（新）。
- Sources/LefuCore/LyricsDocument.swift — LRC/KRC 结构化解析（新）。
- Tests/LefuCoreTests/ColorMathTests.swift — 颜色数学测试（新）。
- Tests/LefuCoreTests/LyricsDocumentTests.swift — 歌词解析测试（新）。
- Sources/Lefu/Engine/ArtworkColorService.swift — 封面到主色，带缓存（新）。
- Sources/Lefu/Engine/Notifier.swift — 系统通知 + 触感（新）。
- Sources/Lefu/Views/AmbientBackground.swift — 模糊封面 + 遮罩，交叉淡入（新）。
- Sources/Lefu/Views/LibraryGrid.swift — 轻量封面墙 + Quick Look（新）。
- Sources/Lefu/Theme.swift — 运行时 accent 派生（改）。
- Sources/Lefu/LefuApp.swift — 主题接入 session.coverAccent（改）。
- Sources/Lefu/Engine/SessionController.swift — 发布 coverAccent、歌词文档、波形历史、通知钩子（改）。
- Sources/Lefu/Engine/Lyrics.swift、Engine/SodaLyrics.swift — 接 LyricsDocument（改）。
- Sources/Lefu/Views/RecordView.swift、Views/RootView.swift、Views/MeterWave.swift — 接入视觉（改）。

---

### Task 1: LefuCore 库与颜色数学（TDD）

**Files:**
- Modify: Package.swift
- Create: Sources/LefuCore/ColorMath.swift
- Create: Tests/LefuCoreTests/ColorMathTests.swift

**Interfaces:**
- Produces: RGB(r:g:b:)，AccentDerivation.clamp(_:minL:maxL:minS:maxS:) -> RGB?，AccentDerivation.toHSL(_:) -> (h:Double,s:Double,l:Double)，AccentDerivation.fromHSL(h:s:l:) -> RGB

- [ ] **Step 1: 改 Package.swift，加库目标与测试目标**

    targets: [
        .target(
            name: "LefuCore",
            path: "Sources/LefuCore"
        ),
        .executableTarget(
            name: "乐府",
            dependencies: ["LefuCore"],
            path: "Sources/Lefu"
        ),
        .testTarget(
            name: "LefuCoreTests",
            dependencies: ["LefuCore"],
            path: "Tests/LefuCoreTests"
        )
    ],

- [ ] **Step 2: 写失败测试 Tests/LefuCoreTests/ColorMathTests.swift**

    import XCTest
    @testable import LefuCore

    final class ColorMathTests: XCTestCase {
        func testPureGrayReturnsNil() {
            XCTAssertNil(AccentDerivation.clamp(RGB(r: 0.5, g: 0.5, b: 0.5)))
        }
        func testLowSaturationReturnsNil() {
            XCTAssertNil(AccentDerivation.clamp(RGB(r: 0.50, g: 0.48, b: 0.46)))
        }
        func testSaturatedDarkColorIsBrightened() {
            let out = AccentDerivation.clamp(RGB(r: 0.10, g: 0.02, b: 0.20))!
            let (_, s, l) = AccentDerivation.toHSL(out)
            XCTAssertGreaterThanOrEqual(l, 0.44)
            XCTAssertLessThanOrEqual(l, 0.73)
            XCTAssertGreaterThanOrEqual(s, 0.34)
        }
        func testHueIsPreserved() {
            let input = RGB(r: 0.9, g: 0.4, b: 0.1)
            let (h0, _, _) = AccentDerivation.toHSL(input)
            let out = AccentDerivation.clamp(input)!
            let (h1, _, _) = AccentDerivation.toHSL(out)
            XCTAssertEqual(h0, h1, accuracy: 0.01)
        }
    }

- [ ] **Step 3: 跑测试确认失败**

Run: swift test --filter ColorMathTests
Expected: 编译失败（找不到 LefuCore / AccentDerivation）

- [ ] **Step 4: 实现 Sources/LefuCore/ColorMath.swift**

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

- [ ] **Step 5: 跑测试确认通过**

Run: swift test --filter ColorMathTests
Expected: PASS（4 个）

- [ ] **Step 6: 提交**

    git add Package.swift Sources/LefuCore Tests/LefuCoreTests
    git commit -m "feat(core): LefuCore 库 + 封面强调色钳制"

---

### Task 2: ArtworkColorService 与 SessionController.coverAccent

**Files:**
- Create: Sources/Lefu/Engine/ArtworkColorService.swift
- Modify: Sources/Lefu/Engine/SessionController.swift

**Interfaces:**
- Consumes: LefuCore.AccentDerivation、RGB
- Produces: ArtworkColorService.accent(forKey:image:completion:)、SessionController.coverAccent: Color?

- [ ] **Step 1: 新增 Sources/Lefu/Engine/ArtworkColorService.swift**

    import AppKit
    import CoreImage
    import LefuCore

    /// 从封面提取主色并钳制为强调色。异步 + 按 key 缓存，绝不占用主线程。
    final class ArtworkColorService {
        private let context = CIContext(options: [.workingColorSpace: NSNull()])
        private var cache: [String: NSColor] = [:]

        func accent(forKey key: String, image: NSImage, completion: @escaping (NSColor?) -> Void) {
            if let cached = cache[key] { completion(cached); return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let color = self.extract(image)
                DispatchQueue.main.async {
                    if let color { self.cache[key] = color }
                    completion(color)
                }
            }
        }

        private func extract(_ image: NSImage) -> NSColor? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let ci = CIImage(cgImage: cg)
            guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
                kCIInputImageKey: ci,
                kCIInputExtentKey: CIVector(cgRect: ci.extent),
            ]), let output = filter.outputImage else { return nil }
            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(output, toBitmap: &bitmap, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            let rgb = RGB(r: Double(bitmap[0]) / 255, g: Double(bitmap[1]) / 255, b: Double(bitmap[2]) / 255)
            guard let clamped = AccentDerivation.clamp(rgb) else { return nil }
            return NSColor(srgbRed: clamped.r, green: clamped.g, blue: clamped.b, alpha: 1)
        }
    }

- [ ] **Step 2: SessionController 增加依赖与发布属性**

在 SessionController.swift 顶部加 import SwiftUI；在类内加：

    @Published var coverAccent: Color?
    private let artworkColor = ArtworkColorService()

- [ ] **Step 3: 抽封面更新入口，替换现有直写 artworkImage 的分支**

    private func updateArtwork(_ info: TrackInfo) {
        guard let art = info.artwork, let img = NSImage(data: art) else { return }
        artworkImage = img
        let key = info.key
        artworkColor.accent(forKey: key, image: img) { [weak self] color in
            guard let self, self.currentTrack?.key == key else { return }
            self.coverAccent = color
        }
    }

在 monitor.onUpdate 里把原来的 if let art = info.artwork, let img = NSImage(data: art) { self.artworkImage = img } 换成 self.updateArtwork(info)；并在 applyMetaCorrection 里 artwork 回填后也调用 updateArtwork(info)。

- [ ] **Step 4: 生命周期清理**

在 startSession() 与 reset() 里各加 coverAccent = nil；stopAndCut() 收尾不清空（保留完成态氛围），reset() 清空。

- [ ] **Step 5: 编译并手动验证**

Run: swift build
Expected: 成功。手动验证 coverAccent 在带封面曲目下被赋值，灰阶封面回落 nil。

- [ ] **Step 6: 提交**

    git add Sources/Lefu/Engine/ArtworkColorService.swift Sources/Lefu/Engine/SessionController.swift
    git commit -m "feat(ui): 封面主色服务与 coverAccent"

---

### Task 3: 运行时主题 + 氛围背景

**Files:**
- Modify: Sources/Lefu/Theme.swift
- Modify: Sources/Lefu/LefuApp.swift
- Create: Sources/Lefu/Views/AmbientBackground.swift
- Modify: Sources/Lefu/Views/RootView.swift

**Interfaces:**
- Consumes: SessionController.coverAccent、session.artworkImage、currentTrack.key
- Produces: LefuTheme.withAccent(_:contrast:)、AmbientBackground(image:key:)

- [ ] **Step 1: Theme.swift 加派生方法**

    extension LefuTheme {
        func withAccent(_ accent: Color, contrast: Color) -> LefuTheme {
            LefuTheme(bg: bg, panel: panel, panel2: panel2, rail: rail,
                      border: border, border2: border2,
                      text: text, text2: text2, text3: text3,
                      accent: accent, accentContrast: contrast,
                      live: live, ok: ok, skip: skip, shadow: shadow)
        }
    }

- [ ] **Step 2: LefuApp 的主题接入封面 accent**

    private var theme: LefuTheme {
        let base: LefuTheme
        switch settings.themeMode {
        case .system:
            base = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .light: base = .light
        case .dark: base = .dark
        }
        guard let accent = session.coverAccent else { return base }
        let isDark = (settings.themeMode == .dark)
            || (settings.themeMode == .system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        return base.withAccent(Color(nsColor: accent), contrast: isDark ? Color.p3(0.08, 0.07, 0.10) : .white)
    }

- [ ] **Step 3: 新增 Sources/Lefu/Views/AmbientBackground.swift**

    import SwiftUI
    import AppKit
    import CoreImage
    import QuartzCore

    enum BlurredCover {
        private static let ctx = CIContext()
        static func make(_ image: NSImage) -> CGImage? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let ci = CIImage(cgImage: cg)
            let blurred = ci.applyingGaussianBlur(sigma: 40).cropped(to: ci.extent)
            return ctx.createCGImage(blurred, from: ci.extent)
        }
    }

    final class AmbientView: NSView {
        private let aLayer = CALayer()
        private let bLayer = CALayer()
        private let scrim = CAGradientLayer()
        private var showingA = true
        var lastKey = ""
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
            scrim.colors = [NSColor.black.withAlphaComponent(0.10).cgColor,
                            NSColor.black.withAlphaComponent(0.55).cgColor]
            scrim.locations = [0, 1]
            layer?.addSublayer(scrim)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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

    struct AmbientBackground: NSViewRepresentable {
        let image: NSImage?
        let key: String
        func makeNSView(context: Context) -> AmbientView { AmbientView() }
        func updateNSView(_ v: AmbientView, context: Context) {
            guard v.lastKey != key else { return }
            v.lastKey = key
            v.setCover(image.flatMap { BlurredCover.make($0) })
            v.hasRendered = true
        }
    }

- [ ] **Step 4: RootView 把氛围背景铺在内容之下**

在 RootView.body 最外层 VStack 的 .background(th.bg) 之前插入：

    .background(alignment: .center) {
        if page == .record, session.currentTrack != nil {
            AmbientBackground(image: session.artworkImage, key: session.currentTrack?.key ?? "")
                .ignoresSafeArea()
        }
    }

- [ ] **Step 5: 编译 + 手动验收**

Run: swift build
手动：播放带封面歌曲，全窗出现模糊封面 + 渐变；切歌 0.6s 交叉淡入；灰阶封面保持纯色底；文字清晰。

- [ ] **Step 6: 提交**

    git add Sources/Lefu/Theme.swift Sources/Lefu/LefuApp.swift Sources/Lefu/Views/AmbientBackground.swift Sources/Lefu/Views/RootView.swift
    git commit -m "feat(ui): 封面驱动的氛围背景与运行时主题"

### Task 4: LyricsDocument（LefuCore, TDD）

**Files:**
- Create: Sources/LefuCore/LyricsDocument.swift
- Create: Tests/LefuCoreTests/LyricsDocumentTests.swift

**Interfaces:**
- Produces: LyricWord(start:duration:text:)、LyricLine(start:text:words:)、LyricsDocument(lines:)、LyricsDocument.parseLRC(_:)、LyricsDocument.parseKRC(_:)、LyricsDocument.currentLineIndex(at:)、LyricsDocument.toLRC()

- [ ] **Step 1: 写失败测试 Tests/LefuCoreTests/LyricsDocumentTests.swift**

    import XCTest
    @testable import LefuCore

    final class LyricsDocumentTests: XCTestCase {
        func testParseLRCWithMultipleTags() {
            let doc = LyricsDocument.parseLRC("[00:01.00][00:02.00]hi\n[00:03.50]bye")
            XCTAssertEqual(doc.lines.map { $0.start }, [1.0, 2.0, 3.5])
            XCTAssertEqual(doc.lines.map { $0.text }, ["hi", "hi", "bye"])
        }
        func testCurrentLineIndex() {
            let doc = LyricsDocument.parseLRC("[00:01.00]a\n[00:05.00]b")
            XCTAssertEqual(doc.currentLineIndex(at: 0.5), -1)
            XCTAssertEqual(doc.currentLineIndex(at: 1.0), 0)
            XCTAssertEqual(doc.currentLineIndex(at: 9.0), 1)
        }
        func testParseKRCKeepsWordTimings() {
            let raw = "[1000,2000]<0,500,0>Hel<500,500,0>lo"
            let doc = LyricsDocument.parseKRC(raw)
            XCTAssertEqual(doc.lines.count, 1)
            XCTAssertEqual(doc.lines[0].text, "Hello")
            XCTAssertEqual(doc.lines[0].start, 1.0, accuracy: 0.001)
            XCTAssertEqual(doc.lines[0].words.count, 2)
            XCTAssertEqual(doc.lines[0].words[1].start, 1.5, accuracy: 0.001)
        }
        func testToLRCRoundTrip() {
            let doc = LyricsDocument.parseKRC("[1000,2000]<0,500,0>Hi")
            XCTAssertTrue(doc.toLRC().contains("[00:01.00]Hi"))
        }
    }

- [ ] **Step 2: 跑测试确认失败**

Run: swift test --filter LyricsDocumentTests
Expected: 编译失败（找不到 LyricsDocument）

- [ ] **Step 3: 实现 Sources/LefuCore/LyricsDocument.swift**

    import Foundation

    public struct LyricWord: Equatable {
        public let start: Double
        public let duration: Double
        public let text: String
        public init(start: Double, duration: Double, text: String) {
            self.start = start; self.duration = duration; self.text = text
        }
    }

    public struct LyricLine: Equatable {
        public let start: Double
        public let text: String
        public let words: [LyricWord]
        public init(start: Double, text: String, words: [LyricWord] = []) {
            self.start = start; self.text = text; self.words = words
        }
    }

    public struct LyricsDocument: Equatable {
        public let lines: [LyricLine]
        public init(lines: [LyricLine]) { self.lines = lines }

        public func currentLineIndex(at t: Double) -> Int {
            var idx = -1
            for (i, l) in lines.enumerated() where l.start <= t { idx = i }
            return idx
        }

        public static func parseLRC(_ raw: String) -> LyricsDocument {
            var out: [LyricLine] = []
            for line in raw.components(separatedBy: .newlines) {
                let times = lrcTimes(line)
                let text = line.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, !times.isEmpty else { continue }
                for t in times { out.append(LyricLine(start: t, text: text)) }
            }
            return LyricsDocument(lines: out.sorted { $0.start < $1.start })
        }

        public static func parseKRC(_ raw: String) -> LyricsDocument {
            let lineRe = try! NSRegularExpression(pattern: #"\[(\d{3,7}),(\d{3,7})\]((?:<\d{1,6},\d{1,6},\d{1,2}>[^\n\[]*)+)"#)
            let wordRe = try! NSRegularExpression(pattern: #"<(\d{1,6}),(\d{1,6}),\d{1,2}>([^\n<]*)"#)
            let ns = raw as NSString
            var out: [LyricLine] = []
            lineRe.enumerateMatches(in: raw, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m, m.range(at: 1).location != NSNotFound, m.range(at: 2).location != NSNotFound else { return }
                let startMs = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let body = ns.substring(with: m.range(at: 2))
                let bns = body as NSString
                var words: [LyricWord] = []
                var text = ""
                wordRe.enumerateMatches(in: body, range: NSRange(location: 0, length: bns.length)) { wm, _, _ in
                    guard let wm, wm.range(at: 3).location != NSNotFound else { return }
                    let off = Double(bns.substring(with: wm.range(at: 1))) ?? 0
                    let dur = Double(bns.substring(with: wm.range(at: 2))) ?? 0
                    let w = bns.substring(with: wm.range(at: 3))
                    words.append(LyricWord(start: (startMs + off) / 1000, duration: dur / 1000, text: w))
                    text += w
                }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { out.append(LyricLine(start: startMs / 1000, text: trimmed, words: words)) }
            }
            return LyricsDocument(lines: out.sorted { $0.start < $1.start })
        }

        public func toLRC() -> String {
            lines.map { String(format: "[%02d:%02d.%02d]%@", Int($0.start) / 60, Int($0.start) % 60, Int(($0.start * 100).rounded()) % 100, $0.text) }
                .joined(separator: "\n")
        }

        private static func lrcTimes(_ line: String) -> [Double] {
            var result: [Double] = []
            let pattern = #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
            let ns = line as NSString
            regex.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m else { return }
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let fs = ns.substring(with: m.range(at: 3))
                    frac = (Double(fs) ?? 0) / pow(10, Double(fs.count))
                }
                result.append(mm * 60 + ss + frac)
            }
            return result
        }
    }

- [ ] **Step 4: 跑测试确认通过**

Run: swift test --filter LyricsDocumentTests
Expected: PASS（4 个）

- [ ] **Step 5: 提交**

    git add Sources/LefuCore/LyricsDocument.swift Tests/LefuCoreTests/LyricsDocumentTests.swift
    git commit -m "feat(core): 结构化歌词文档（LRC/KRC，保留词段时间轴）"

---

### Task 5: 歌词接入 App

**Files:**
- Modify: Sources/Lefu/Engine/SodaLyrics.swift
- Modify: Sources/Lefu/Engine/Lyrics.swift
- Modify: Sources/Lefu/Engine/SessionController.swift
- Modify: Sources/Lefu/Views/RecordView.swift

**Interfaces:**
- Consumes: LefuCore.LyricsDocument
- Produces: SodaLyrics.localKRC(title:artist:)、LyricsFetcher.fetchDocument(...)、SessionController.lyrics: LyricsDocument

- [ ] **Step 1: SodaLyrics 暴露原始 KRC**

scanIndex 里把 krc 字段改成保留原始 KRC 文本：将 let krc = krcToLrc(raw) 改为 let krc = String(decoding: raw, as: UTF8.self)。再加入口：

    static func localKRC(title: String, artist: String) -> String? {
        guard !title.isEmpty, let data = try? Data(contentsOf: dbURL) else { return nil }
        let bytes = [UInt8](data)
        let index = scanIndex(bytes: bytes, size: data.count)
        let artistB = Array(artist.utf8)
        for tid in titleCandidates(bytes, title: title) {
            if let entry = index[tid], entry.krcLrc.count > 30, artistOK(bytes, tid: tid, artistB: artistB) {
                return entry.krcLrc
            }
        }
        return nil
    }

- [ ] **Step 2: LyricsFetcher 增加结构化入口**

    static func fetchDocument(title: String, artist: String, duration: Double,
                              offline: Bool, fallback: Bool, cacheDir: URL?) async -> LyricsDocument? {
        if let krc = SodaLyrics.localKRC(title: title, artist: artist), !krc.isEmpty {
            let doc = LyricsDocument.parseKRC(krc)
            if !doc.lines.isEmpty { return doc }
        }
        guard let lrc = await fetchLRC(title: title, artist: artist, duration: duration,
                                       offline: offline, fallback: fallback, cacheDir: cacheDir) else { return nil }
        return LyricsDocument.parseLRC(lrc)
    }

- [ ] **Step 3: SessionController 用 LyricsDocument**

把 @Published var lyricLines: [(Double, String)] = [] 与 lyricIndex 换成：

    @Published var lyrics = LyricsDocument(lines: [])
    @Published var lyricIndex: Int = -1

tickTimer 内改为 box.lyricIndex = box.lyrics.currentLineIndex(at: offset)；confirmTrack 的歌词预取改调 fetchDocument 并赋值 self.lyrics。

- [ ] **Step 4: RecordView 渲染整行 + 可选逐字**

当前行取 session.lyrics.lines[safe: session.lyricIndex]，下一行 +1；当前行 words 非空且 songPos 落在行内则按词高亮，否则整行亮；整行切换用 .animation(.easeInOut(duration: 0.3))。

- [ ] **Step 5: 编译 + 手动验收**

Run: swift build
手动：汽水本地有 KRC 的歌确认逐字高亮；无 KRC 的歌整行切换；LRCLIB/网易云来源正常。

- [ ] **Step 6: 提交**

    git add Sources/Lefu/Engine/SodaLyrics.swift Sources/Lefu/Engine/Lyrics.swift Sources/Lefu/Engine/SessionController.swift Sources/Lefu/Views/RecordView.swift
    git commit -m "feat(ui): 歌词整行滚动与 KRC 逐字高亮"

---

### Task 6: 真实波形历史

**Files:**
- Modify: Sources/Lefu/Engine/SessionController.swift（LevelMeter）
- Modify: Sources/Lefu/Views/MeterWave.swift

**Interfaces:**
- Produces: LevelMeter.history: [Float]（长度 48，最新在尾）

- [ ] **Step 1: LevelMeter 增环形缓冲**

    private var buffer = [Float](repeating: 0, count: 48)
    @Published private(set) var history: [Float] = Array(repeating: 0, count: 48)

    func push(_ v: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastPush) >= 0.06 || abs(v - level) > 0.06 else { return }
        lastPush = now
        level = v
        buffer.removeFirst()
        buffer.append(v)
        history = buffer
    }

    func reset() { level = 0; buffer = Array(repeating: 0, count: 48); history = buffer }

- [ ] **Step 2: MeterWaveView 用真实历史替换伪随机柱**

bind 改为订阅 meter.$history；render(history:) 每根柱高度 = bounds.height * CGFloat(0.08 + history[i] * 0.92)，去掉 (i*37)%23 噪声与 (i%3==0) 权重，opacity 统一 1。

- [ ] **Step 3: 编译 + 手动验收**

Run: swift build
手动：柱子随电平真实起伏；静音归零；录制 30 分钟不卡顿。

- [ ] **Step 4: 提交**

    git add Sources/Lefu/Engine/SessionController.swift Sources/Lefu/Views/MeterWave.swift
    git commit -m "feat(ui): 真实电平历史波形"

---

### Task 7: 完成通知 + 触感 + 封卷仪式

**Files:**
- Create: Sources/Lefu/Engine/Notifier.swift
- Modify: Sources/Lefu/Engine/SessionController.swift
- Modify: Sources/Lefu/Views/RecordView.swift

**Interfaces:**
- Produces: Notifier.requestAuthorization()、Notifier.songCaptured(title:artist:)、Notifier.tap()

- [ ] **Step 1: 新增 Sources/Lefu/Engine/Notifier.swift**

    import AppKit
    import UserNotifications

    enum Notifier {
        static func requestAuthorization() {
            guard Bundle.main.bundleIdentifier != nil else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        static func songCaptured(title: String, artist: String) {
            guard Bundle.main.bundleIdentifier != nil, !title.isEmpty else { return }
            let content = UNMutableNotificationContent()
            content.title = "已收录"
            content.body = artist.isEmpty ? title : artist + " — " + title
            content.sound = .default
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
        static func tap() {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

- [ ] **Step 2: 在 Cutter onAllDone 成功分支触发**

onAllDone 的 case .done: 内加：Notifier.songCaptured(title: task.entry.title, artist: task.entry.artist) 与 Notifier.tap()。

- [ ] **Step 3: 启动时申请一次权限**

SessionController.init 末尾调用 Notifier.requestAuthorization()。

- [ ] **Step 4: 封卷动效**

在 RecordView cuttingView/doneView 主徽章外用 PulseRing/PulseHalo 包一层（沿用现有 CA 层组件），禁止 repeatForever。

- [ ] **Step 5: 编译 + 手动验收**

Run: swift build，然后 bash scripts/build_app.sh && open build/.dist/乐府.app
手动：收到带曲名的系统通知；收卷徽章呼吸；触控板触感。

- [ ] **Step 6: 提交**

    git add Sources/Lefu/Engine/Notifier.swift Sources/Lefu/Engine/SessionController.swift Sources/Lefu/Views/RecordView.swift
    git commit -m "feat(ui): 完成通知、触感与封卷仪式"

---

### Task 8: 视觉层次（材质 / 空态 / 对比度）

**Files:**
- Modify: Sources/Lefu/Views/RootView.swift
- Modify: Sources/Lefu/Views/RecordView.swift
- Modify: Sources/Lefu/Theme.swift

**Interfaces:**
- Consumes: LefuTheme

- [ ] **Step 1: 材质关系收口**

标题栏保持 .regularMaterial，侧栏 .ultraThinMaterial，卡片统一 lefuCard(th, radius: 12)，分隔线统一 th.border。

- [ ] **Step 2: 补齐空态**

libraryRail 在 library.recent 为空时显示空态（图标 + 「还没有采到歌，点中央开始」）；采录中列表为空同理。

- [ ] **Step 3: 对比度自检**

两个主题下对照背景手工算 th.text/th.text2 对比度；正文 ≥ 4.5:1，辅助 ≥ 3:1，不达标只改 Theme.swift 数值。

- [ ] **Step 4: 编译 + 四态走查**

Run: swift build
手动：待机 / 采录中 / 收卷 / 完成，深浅两主题各截图对照 DESIGN token。

- [ ] **Step 5: 提交**

    git add Sources/Lefu/Views/RootView.swift Sources/Lefu/Views/RecordView.swift Sources/Lefu/Theme.swift
    git commit -m "feat(ui): 视觉层次、空态与对比度收口"

---

### Task 9: 府库轻量封面墙

**Files:**
- Modify: Sources/Lefu/Engine/SessionController.swift
- Create: Sources/Lefu/Views/LibraryGrid.swift
- Modify: Sources/Lefu/Views/RootView.swift

**Interfaces:**
- Consumes: SessionController.library、OutputItem、CoverExtractor
- Produces: LibraryGrid(session:theme:)、LibraryStats.all

- [ ] **Step 1: refreshLibrary 保留完整清单**

LibraryStats 加 var all: [OutputItem] = []；refreshLibrary 里 all = items（排序后），recent 仍 prefix(12)。

- [ ] **Step 2: 新增 Sources/Lefu/Views/LibraryGrid.swift**

    import SwiftUI
    import AppKit

    struct LibraryGrid: View {
        @ObservedObject var session: SessionController
        @Environment(\.lefuTheme) var th
        private let columns = [GridItem(.adaptive(minimum: 148), spacing: 16)]

        var body: some View {
            ScrollView {
                if session.library.all.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list").font(.system(size: 28)).foregroundColor(th.text3)
                        Text("府库还空着").font(.lefu(.body)).foregroundColor(th.text2)
                    }.frame(maxWidth: .infinity).padding(.top, 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(session.library.all) { item in
                            LibraryCell(item: item, theme: th)
                        }
                    }.padding(20)
                }
            }
            .background(th.bg)
        }
    }

    private struct LibraryCell: View {
        let item: OutputItem
        let theme: LefuTheme
        @State private var hover = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.panel2)
                    if let cover = item.cover {
                        Image(nsImage: cover).resizable().scaledToFill()
                    } else {
                        Image(systemName: "music.note").font(.system(size: 24)).foregroundColor(theme.text3)
                    }
                }
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: hover ? theme.shadow : .clear, radius: 10, y: 4)
                .scaleEffect(hover ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
                Text(item.name).font(.lefu(.callout)).foregroundColor(theme.text).lineLimit(1)
            }
            .onHover { hover = $0 }
            .contextMenu {
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.id]) }
            }
            .onTapGesture(count: 2) { NSWorkspace.shared.open(item.id) }
        }
    }

- [ ] **Step 3: RootView 增加导航入口**

Page 枚举加 case library = "曲库"（icon "square.grid.2x2"），页面映射到 LibraryGrid(session: session, theme: th)。

- [ ] **Step 4: 编译 + 手动验收**

Run: swift build
手动：府库页显示封面墙；双击用系统默认播放器打开；右键在访达显示；空态正确。

- [ ] **Step 5: 提交**

    git add Sources/Lefu/Engine/SessionController.swift Sources/Lefu/Views/LibraryGrid.swift Sources/Lefu/Views/RootView.swift
    git commit -m "feat(ui): 府库轻量封面墙"

---

## Self-Review

- **Spec coverage:** #14→Task2/3；#15→Task4/5；#16→Task9；#17→Task8；#18→Task6/7；真实波形→Task6；封卷仪式→Task7；菜单栏封面→Task8 可顺带（未单列）；主题扩展→Task3 基座，纸墨主题后续。
- **Placeholder scan:** 无 TBD/TODO；每个代码步骤都有可粘贴代码或明确替换点。
- **Type consistency:** RGB/AccentDerivation（Task1→2）；LyricsDocument/LyricLine/LyricWord（Task4→5）；coverAccent（Task2→3）；LevelMeter.history（Task6）；LibraryStats.all（Task9）。

## 已知偏离 spec 的取舍

- 封面取色用 CIAreaAverage + 钳制，而非 k-means；低饱和/灰阶直接回落。
- 逐字高亮只在汽水本地 KRC 源可用，其他源整行滚动。
- 府库右键「重裁」未实现（源 WAV 出片后已清理，无源可重裁），改为在访达显示 + 双击打开。
- 「菜单栏封面」未单列任务，若要做在 Task8 顺带。
