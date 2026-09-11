# 多音源 Provider 重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 把代码结构改为以「音源档案」为中心，使「适配一个音乐软件」= 新增一份档案（可选带本地歌词解析器），并把汽水等价迁移，行为不变。

**Architecture:** 纯数据音源档案 + 音源登记处 + 歌词后端抽象 + 监听层暴露客户端标识。差异全部收进档案，引擎不含任何具体软件的分支。

**Tech Stack:** Swift 5.9 · SwiftUI · CoreAudio · LefuCore（纯逻辑）· 无第三方依赖。

**Spec:** docs/superpowers/specs/2026-09-11-multi-source-provider-design.md

## Global Constraints

- macOS 13+；swiftLanguageVersions [.v5]。
- 无第三方依赖；输出/命名/编码策略不变。
- 纯逻辑下沉 LefuCore 并可单测；本机无 XCTest，本地用 .superpowers/sdd 的 xctest-shim 路子验证，CI（Xcode 15.4）权威。
- 默认只启用汽水；本次重构期间汽水行为必须与现状逐项一致。
- 持久动画只用 Core Animation，禁止 SwiftUI repeatForever。
- 不用 backtick 之外的东西不重要；本计划所有代码块用四空格缩进。

## File Structure

- Create: Sources/LefuCore/SourceModel.swift — 音源纯数据模型与目录解析
- Create: Tests/LefuCoreTests/SourceCatalogTests.swift — 纯逻辑单测
- Create: Sources/Lefu/Sources/MusicSource.swift — 音源协议与登记处
- Create: Sources/Lefu/Sources/SodaSource.swift — 汽水档案
- Create: Sources/Lefu/Engine/LyricsBackend.swift — 歌词后端协议
- Create: Sources/Lefu/Engine/SodaLocalLyricsBackend.swift — 汽水本地后端（包装 SodaLyrics）
- Modify: Sources/Lefu/Engine/NowPlaying.swift — 暴露 clientBundle，去掉硬编码过滤
- Modify: Sources/Lefu/Engine/Lyrics.swift — 按后端 + 通用链组合
- Modify: Sources/Lefu/Engine/SessionController.swift — 登记处门禁与档案接线
- Modify: Sources/Lefu/Settings.swift — enabledSourceIDs
- Modify: Sources/Lefu/Views/SettingsView.swift — 音源分区
- Modify: Sources/Lefu/Views/GuideView.swift / RecordView.swift / MenuBarPanel.swift — 文案泛化

---

### Task 1: LefuCore 音源模型与目录解析

**Files:**
- Create: Sources/LefuCore/SourceModel.swift
- Create: Tests/LefuCoreTests/SourceCatalogTests.swift

**Interfaces:**
- Consumes: 无
- Produces: SourceID；PlaySignal；ControlChannel；DetectionProfile；SourceProfile；SourceCatalog.resolve(bundleID:in:)；SourceCatalog.filterEnabled(_:enabled:)

- [ ] **Step 1: 写失败测试**

    // Tests/LefuCoreTests/SourceCatalogTests.swift
    import XCTest
    import LefuCore

    final class SourceCatalogTests: XCTestCase {
        private func soda() -> SourceProfile {
            SourceProfile(
                id: SourceID(raw: "soda"), displayName: "汽水音乐",
                bundleIDs: ["com.soda.music"], symbolName: "music.note",
                detection: DetectionProfile(), control: .nowPlayingCLI,
                lyricsBackendIDs: ["soda.local"], enabledByDefault: true)
        }
        private func netease() -> SourceProfile {
            SourceProfile(
                id: SourceID(raw: "netease"), displayName: "网易云音乐",
                bundleIDs: ["com.netease.163music"], symbolName: "cloud",
                detection: DetectionProfile(playSignal: .elapsedAdvance),
                control: .mediaRemote, lyricsBackendIDs: [], enabledByDefault: false)
        }

        func testResolveByBundleID() {
            let profiles = [soda(), netease()]
            XCTAssertEqual(SourceCatalog.resolve(bundleID: "com.soda.music", in: profiles)?.id.raw, "soda")
            XCTAssertEqual(SourceCatalog.resolve(bundleID: "com.netease.163music", in: profiles)?.id.raw, "netease")
        }
        func testResolveUnknownAndNil() {
            let profiles = [soda()]
            XCTAssertNil(SourceCatalog.resolve(bundleID: "com.spotify.client", in: profiles))
            XCTAssertNil(SourceCatalog.resolve(bundleID: nil, in: profiles))
            XCTAssertNil(SourceCatalog.resolve(bundleID: "", in: profiles))
        }
        func testFilterEnabled() {
            let profiles = [soda(), netease()]
            let enabled = SourceCatalog.filterEnabled(profiles, enabled: ["soda"])
            XCTAssertEqual(enabled.map(\.id.raw), ["soda"])
            XCTAssertTrue(SourceCatalog.filterEnabled(profiles, enabled: ["netease", "soda"]).count == 2)
            XCTAssertTrue(SourceCatalog.filterEnabled(profiles, enabled: []).isEmpty)
        }
        func testDefaultDetectionProfile() {
            let d = DetectionProfile()
            XCTAssertEqual(d.confirmTicks, 2)
            XCTAssertEqual(d.pollInterval, 1.0)
            XCTAssertEqual(d.playSignal, .ratePreferred)
            XCTAssertEqual(d.exposesElapsed, false)   // 汽水 elapsed 恒为 0
        }
    }

- [ ] **Step 2: 跑测试确认失败**

本地用 shim 路子编译 Sources/LefuCore/*.swift + shim + 该测试，预期编译失败（类型不存在）。
CI：swift test。预期 FAIL。

- [ ] **Step 3: 实现 SourceModel.swift**

    // Sources/LefuCore/SourceModel.swift
    import Foundation

    public struct SourceID: Hashable, Sendable {
        public let raw: String
        public init(raw: String) { self.raw = raw }
    }

    public enum PlaySignal: String, Sendable { case ratePreferred, elapsedAdvance }
    public enum ControlChannel: String, Sendable { case mediaRemote, nowPlayingCLI, none }

    public struct DetectionProfile: Sendable {
        public var confirmTicks: Int
        public var pollInterval: TimeInterval
        public var playSignal: PlaySignal
        public var exposesElapsed: Bool
        public var exposesDuration: Bool
        public init(confirmTicks: Int = 2,
                    pollInterval: TimeInterval = 1.0,
                    playSignal: PlaySignal = .ratePreferred,
                    exposesElapsed: Bool = false,
                    exposesDuration: Bool = true) {
            self.confirmTicks = confirmTicks
            self.pollInterval = pollInterval
            self.playSignal = playSignal
            self.exposesElapsed = exposesElapsed
            self.exposesDuration = exposesDuration
        }
    }

    public struct SourceProfile: Sendable, Identifiable {
        public let id: SourceID
        public let displayName: String
        public let bundleIDs: Set<String>
        public let symbolName: String
        public let detection: DetectionProfile
        public let control: ControlChannel
        public let lyricsBackendIDs: [String]
        public let enabledByDefault: Bool
        public init(id: SourceID, displayName: String, bundleIDs: Set<String>,
                    symbolName: String, detection: DetectionProfile = DetectionProfile(),
                    control: ControlChannel = .mediaRemote, lyricsBackendIDs: [String] = [],
                    enabledByDefault: Bool = false) {
            self.id = id; self.displayName = displayName; self.bundleIDs = bundleIDs
            self.symbolName = symbolName; self.detection = detection; self.control = control
            self.lyricsBackendIDs = lyricsBackendIDs; self.enabledByDefault = enabledByDefault
        }
    }

    public enum SourceCatalog {
        public static func resolve(bundleID: String?, in profiles: [SourceProfile]) -> SourceProfile? {
            guard let bundleID, !bundleID.isEmpty else { return nil }
            return profiles.first { $0.bundleIDs.contains(bundleID) }
        }
        public static func filterEnabled(_ profiles: [SourceProfile], enabled: Set<String>) -> [SourceProfile] {
            profiles.filter { enabled.contains($0.id.raw) }
        }
    }

- [ ] **Step 4: 跑测试确认通过**

shim 路子或 CI。预期 PASS（4 个用例）。

- [ ] **Step 5: 提交**

    git add Sources/LefuCore/SourceModel.swift Tests/LefuCoreTests/SourceCatalogTests.swift
    git commit -m "feat(core): 音源档案纯数据模型与目录解析"

---

### Task 2: 监听暴露客户端标识 + 音源登记处 + 已启用门禁

**Files:**
- Modify: Sources/Lefu/Engine/NowPlaying.swift
- Create: Sources/Lefu/Sources/MusicSource.swift
- Create: Sources/Lefu/Sources/SodaSource.swift
- Modify: Sources/Lefu/Settings.swift
- Modify: Sources/Lefu/Engine/SessionController.swift

**Interfaces:**
- Consumes: Task 1 的 SourceProfile / SourceCatalog / SourceID
- Produces: TrackInfo.clientBundle: String?；MusicSource 协议（static profile / static lyricsBackends）；SourceRegistry.shared（allProfiles、profile(forBundle:)、isEnabled(_:)、enabledProfiles）；AppSettings.enabledSourceIDs: [String]

- [ ] **Step 1: TrackInfo 增加 clientBundle，监听层不再硬过滤**

NowPlaying.swift：
- TrackInfo 增加字段 var clientBundle: String? = nil（放在 artwork 之后）。
- fetchCLI()：删除 sodaBundle 与其过滤分支；读取 json["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String 存入 clientBundle。
- fetchMediaRemote()：同样读取 d["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String 存入 clientBundle。
- 删除静态常量 sodaBundle。
- 保持：标题为空返回 nil；artwork 解析逻辑不变。

- [ ] **Step 2: MusicSource 协议与登记处**

    // Sources/Lefu/Sources/MusicSource.swift
    import Foundation
    import LefuCore

    protocol MusicSource: AnyObject {
        static var profile: SourceProfile { get }
        static var lyricsBackends: [LyricsBackend] { get }
    }
    extension MusicSource { static var lyricsBackends: [LyricsBackend] { [] } }

    final class SourceRegistry {
        static let shared = SourceRegistry(sources: [SodaSource.self])
        private let types: [any MusicSource.Type]
        init(sources: [any MusicSource.Type]) { self.types = sources }

        var allProfiles: [SourceProfile] { types.map { $0.profile } }

        func profile(forBundle bundleID: String?) -> SourceProfile? {
            SourceCatalog.resolve(bundleID: bundleID, in: allProfiles)
        }
        func profile(forID id: String) -> SourceProfile? {
            allProfiles.first { $0.id.raw == id }
        }
        func isEnabled(_ bundleID: String?, enabled: [String]) -> Bool {
            guard let p = profile(forBundle: bundleID) else { return false }
            return enabled.contains(p.id.raw)
        }
        func backends(for profile: SourceProfile) -> [LyricsBackend] {
            let type = types.first { $0.profile.id == profile.id }
            return type?.lyricsBackends ?? []
        }
    }

- [ ] **Step 3: SodaSource 档案**

    // Sources/Lefu/Sources/SodaSource.swift
    import LefuCore
    final class SodaSource: MusicSource {
        static let profile = SourceProfile(
            id: SourceID(raw: "soda"),
            displayName: "汽水音乐",
            bundleIDs: ["com.soda.music"],
            symbolName: "music.note",
            detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                        playSignal: .ratePreferred, exposesElapsed: false),
            control: .nowPlayingCLI,
            lyricsBackendIDs: ["soda.local"],
            enabledByDefault: true)
    }

- [ ] **Step 4: AppSettings 增加 enabledSourceIDs**

Settings.swift：
- @Published var enabledSourceIDs: [String] { didSet { UserDefaults.standard.set(enabledSourceIDs, forKey: "enabledSourceIDs") } }
- init 中：let saved = d.stringArray(forKey: "enabledSourceIDs"); self.enabledSourceIDs = saved ?? SourceRegistry.shared.allProfiles.filter { $0.enabledByDefault }.map { $0.id.raw }

- [ ] **Step 5: SessionController 门禁**

- onUpdate 闭包开头增加门禁：拿到 info 后，若 !SourceRegistry.shared.isEnabled(info.clientBundle, enabled: settings.enabledSourceIDs) 则 return（不更新 currentTrack、不确认、不录）。
- bgHandle 同理：非启用源直接 break。
- 其余逻辑保持不变。

- [ ] **Step 6: 编译并提交**

    swift build --disable-sandbox
    git add ...
    git commit -m "feat(engine): 监听暴露客户端标识，引入音源登记处与启用门禁"

---

### Task 3: 歌词后端抽象与歌词链重组

**Files:**
- Create: Sources/Lefu/Engine/LyricsBackend.swift
- Create: Sources/Lefu/Engine/SodaLocalLyricsBackend.swift
- Modify: Sources/Lefu/Engine/Lyrics.swift
- Modify: Sources/Lefu/Sources/SodaSource.swift
- Modify: Sources/Lefu/Engine/SessionController.swift

**Interfaces:**
- Consumes: Task 1/2
- Produces: LyricsBackend 协议；SodaLocalLyricsBackend；LyricsFetcher.fetchDocument(..., localBackends: [LyricsBackend])

- [ ] **Step 1: 后端协议与汽水实现**

    // Sources/Lefu/Engine/LyricsBackend.swift
    import Foundation
    import LefuCore
    protocol LyricsBackend {
        func document(title: String, artist: String, duration: Double) async -> LyricsDocument?
    }
    final class SodaLocalLyricsBackend: LyricsBackend {
        func document(title: String, artist: String, duration: Double) async -> LyricsDocument? {
            if let krc = SodaLyrics.localKRC(title: title, artist: artist), !krc.isEmpty {
                let d = LyricsDocument.parseKRC(krc)
                if !d.lines.isEmpty { return d }
            }
            if let lrc = SodaLyrics.localLyrics(title: title, artist: artist), !lrc.isEmpty {
                let d = LyricsDocument.parseLRC(lrc)
                if !d.lines.isEmpty { return d }
            }
            return nil
        }
    }

- [ ] **Step 2: SodaSource 提供后端**

SodaSource 增加：static let lyricsBackends: [LyricsBackend] = [SodaLocalLyricsBackend()]。

- [ ] **Step 3: 重组 LyricsFetcher**

- fetchDocument 增加参数 localBackends: [LyricsBackend]（默认 []）。
- 先遍历 localBackends 取 document，命中即返回。
- 再走现有 fetchLRC（自建缓存 → LRCLIB → 网易）；其中**删除**对 SodaLyrics 的直接调用（第 14-16 行的汽水本地分支）——本地能力现在只经后端提供。
- fetchLRC 保留缓存与在线链路；不再引用 SodaLyrics。
- 保留离线语义：离线时只走自建缓存（本就在 fetchLRC 第一步）。

- [ ] **Step 4: SessionController 传后端**

歌词预取处：let source = SourceRegistry.shared.profile(forBundle: info.clientBundle)
let backends = source.map { SourceRegistry.shared.backends(for: $0) } ?? []
调用 fetchDocument(..., localBackends: backends)。

- [ ] **Step 5: 编译并提交**

    swift build --disable-sandbox
    git commit -m "refactor(lyrics): 歌词后端抽象，汽水本地歌词经 provider 提供"

---

### Task 4: 判定与控制按音源档案接线

**Files:**
- Modify: Sources/Lefu/Engine/SessionController.swift
- Modify: Sources/Lefu/Engine/NowPlaying.swift

**Interfaces:**
- Consumes: SourceProfile.detection / .control
- Produces: NowPlayingControl.next(channel: ControlChannel) -> Bool；SessionController.currentSourceProfile: SourceProfile?

- [ ] **Step 1: 控制通道参数化**

NowPlaying.swift：把 NowPlayingControl.next() 改为 next(channel: ControlChannel) -> Bool：
- .none → return false
- .nowPlayingCLI：先试 nowplaying-cli（现有逻辑），失败回落 MediaRemote
- .mediaRemote：直接 sendMediaRemoteCommand("kMRNextTrack")
保留原 next() 为空壳调用 next(channel: .nowPlayingCLI) 之外不要保留；直接改调用点。

- [ ] **Step 2: SessionController 缓存当前音源档案**

- 增加 @Published private(set) var currentSourceProfile: SourceProfile? = nil
- startSession()/onUpdate/bgHandle 解析到启用源时设置它；reset/stop 时清空。

- [ ] **Step 3: 判定参数化**

- monitor.start(interval:) 用 currentSourceProfile?.detection.pollInterval ?? 1.0（确认源后按档案；启动时默认 1.0）。
- 确认器阈值 pendingStableCount >= ticks，其中 ticks = currentSourceProfile?.detection.confirmTicks ?? 2。汽水=2 不变。
- bgIsPlaying 改为按 playSignal：.ratePreferred 走现有 rate>0 优先、缺失退回进度；.elapsedAdvance 直接用进度推进。汽水行为不变。

- [ ] **Step 4: nextTrack 用档案通道与文案**

let channel = currentSourceProfile?.control ?? .mediaRemote
let ok = NowPlayingControl.next(channel: channel)
toast：成功「已切下一阕」；失败按 currentSourceProfile?.displayName 给出「切歌失败：<源> 无可用控制通道」。

- [ ] **Step 5: 编译并提交**

    swift build --disable-sandbox
    git commit -m "refactor(engine): 切歌判定与控制按音源档案接线"

---

### Task 5: 设置「音源」分区

**Files:**
- Modify: Sources/Lefu/Views/SettingsView.swift

**Interfaces:**
- Consumes: AppSettings.enabledSourceIDs；SourceRegistry.shared.allProfiles
- Produces: 设置页音源分区

- [ ] **Step 1: 增加音源分区**

在合适分区位置新增「音源」分区：
- 标题与说明：「只录制勾选的软件，避免误录视频/播客」。
- 遍历 SourceRegistry.shared.allProfiles，每行：SF Symbol + displayName + Toggle。
- Toggle 绑定：enabledSourceIDs 含该源 id.raw 时开；切换时增删。
- 至少保证汽水一项；若用户关掉全部，给出提示但不强制。

- [ ] **Step 2: 编译并提交**

    swift build --disable-sandbox
    git commit -m "feat(settings): 新增音源分区（默认仅汽水）"

---

### Task 6: 文案泛化与来源标识

**Files:**
- Modify: Sources/Lefu/Views/GuideView.swift
- Modify: Sources/Lefu/Views/RecordView.swift
- Modify: Sources/Lefu/Views/MenuBarPanel.swift
- Modify: Sources/Lefu/Views/SettingsView.swift

**Interfaces:**
- Consumes: SourceRegistry.shared.allProfiles
- Produces: 泛化文案；仅多源时显示来源徽章

- [ ] **Step 1: 文案泛化**

- SettingsView：「检测到汽水开播…」→「检测到所选音源开播…」；「只用汽水本地歌词缓存」→「只用本地歌词缓存」。
- GuideView：步骤/FAQ 中「汽水音乐」→「你的音乐软件」或按启用源动态；保留具体操作步骤可读。
- RecordView:58「监听汽水正在播放的内容…」→「监听所选音源正在播放的内容…」。
- MenuBarPanel:108「汽水开播即自动采诗」→「所选音源开播即自动采诗」。

- [ ] **Step 2: 来源徽章（仅多源）**

- TrackRow 增加 var sourceName: String? = nil，确认入列时写入 currentSourceProfile?.displayName。
- RecordView 行内：仅当 settings.enabledSourceIDs.count > 1 且 sourceName 非空时，显示一个小号来源标签。
- 单源（默认仅汽水）时视觉与现状一致。

- [ ] **Step 3: 编译并提交**

    swift build --disable-sandbox
    git commit -m "feat(ui): 文案泛化到多音源，多源时显示来源标识"

---

## Plan Self-Review

- Spec 覆盖：音源档案(T1/T2)、登记处(T2)、歌词后端(T3)、判定与控制(T4)、设置音源分区(T5)、文案与来源(T6)、默认仅汽水(T2/T5)、汽水等价(贯穿)、验收测试(T1)。
- 占位符扫描：无 TBD/TODO；代码步骤均给实现。
- 类型一致性：SourceID/SourceProfile/DetectionProfile 在 T1 定义，T2-T6 一致引用；MusicSource/lyricsBackends 在 T2 定义、T3 扩展；NowPlayingControl.next(channel:) 在 T4 定义并只在该任务改调用点。
- 6.x 中的 exposesElapsed 本期仅入档，不改显示（保持汽水行为）；已在 Task 4 注记。
