import Foundation
import Combine
import AppKit
import SwiftUI
import LefuCore

// MARK: - 采诗页五个中间态
enum RecState: Equatable {
    case idle, live, cutting, done
}

// MARK: - 曲目行
struct TrackRow: Identifiable {
    enum Status: Equatable {
        case recording    // 正在采录（音频写入中）
        case pending      // 已收卷，等待流水线认领（切歌/收卷瞬间）
        case processing   // 流水线处理中（工序见 stageLabel：切段/编码/签章/歌词）
        case captured     // 成品已落盘（MP3 真正写完才到此态）
        case skipped      // 库中已有 / 过短 / 纯静音
    }
    let id: Int
    var title: String
    var artist: String
    var album: String = ""
    var status: Status
    var artwork: NSImage? = nil   // 行内封面缩略图（打点时随 NowPlaying 带入，晚到回填）
    var stageLabel: String = ""   // 裁曲工序实时进度（切段中…/编码中…/✓ 完成），切歌后写回
    var outputPath: String? = nil // 成品 MP3 路径（编码完成后回填，点击行开 Finder）
    var wavPath: String? = nil    // 本首所在录音 WAV（成品未落时点击先定位录音）
    var sizeBytes: Int64 = 0      // 成品大小（已收录后回填，行内展示）
    var seconds: Double = 0       // 成品时长秒（收卷统计时回填，行内展示）
    var midJoin: Bool = false     // 半路接入（本场第一首歌，录制起点在歌中途，绝对进度不可知）
}

// MARK: - 电平表（高频 RMS，独立 ObservableObject）
// 为什么单独拿出来：采集 tap 每 ~46ms 回调一次（2048 帧 @44.1kHz），即每秒 20+ 次电平刷新。
// 若把 level 挂在 SessionController 的 @Published 上，每次刷新都会让「录制台整个 body」重算——
// 而会话队列是上百行非惰性 VStack，行数越多越贵 → 长时间录制后 CPU 常满、界面明显卡顿。
// 独立成对象后，只有波形/电平条这类小叶子视图重绘，队列不再被电平带着一起重画。
final class LevelMeter: ObservableObject {
    @Published private(set) var level: Float = 0
    /// 最近 48 次电平快照（环形缓冲，最新在尾）；只有波形视图订阅它
    @Published private(set) var history: [Float] = Array(repeating: 0, count: 48)
    private var buffer = [Float](repeating: 0, count: 48)
    private var lastPush = Date.distantPast

    /// 节流：最快 ~16Hz，且要有肉眼可见的变化才发布，避免无谓刷新
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
}

// MARK: - 环境检查项
struct EnvCheck: Identifiable {
    enum Status { case pending, checking, ok, fail }
    let id: String
    var status: Status = .pending
    var note: String = ""
}

// MARK: - 完成统计
struct DoneStats {
    var count: Int = 0
    var skippedCount: Int = 0
    var failedCount: Int = 0
    var sizeBytes: Int64 = 0
    var seconds: Double = 0
    var rows: [TrackRow] = []
}

// MARK: - 府库条目（输出目录扫描）
struct OutputItem: Identifiable {
    let id: URL
    let name: String
    let size: Int64
    let date: Date
    var cover: NSImage? = nil   // MP3 内嵌 APIC 封面，异步回填
}

struct LibraryStats {
    var todayCount: Int = 0
    var todayBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var all: [OutputItem] = []
    var recent: [OutputItem] = []
}

// MARK: - 会话控制器
@MainActor
final class SessionController: ObservableObject {
    @Published var state: RecState = .idle
    @Published var envChecks: [EnvCheck] = [
        EnvCheck(id: "blackhole"),
        EnvCheck(id: "channel"),
        EnvCheck(id: "encoder"),
        EnvCheck(id: "route"),
    ]
    @Published var currentTrack: TrackInfo?
    @Published var trackRows: [TrackRow] = []
    @Published var cutTasks: [CutTask] = []
    @Published var cutProgress: Double = 0
    @Published var doneStats = DoneStats()
    @Published var elapsed: Double = 0
    @Published var toast: String?
    @Published var lyrics = LyricsDocument(lines: [])
    @Published var lyricIndex: Int = -1
    @Published var reworkFileURL: URL?
    @Published var artworkImage: NSImage?
    /// 当前封面派生的强调色（异步提取、按 key 缓存；灰阶/低饱和为 nil）
    @Published var coverAccent: Color?
    /// 电平表：独立对象，高频刷新只重绘波形，不惊动整个录制台（见 LevelMeter 注释）
    let meter = LevelMeter()
    @Published var library = LibraryStats()
    @Published var installingBlackHole = false
    @Published var routeReady = false
    private var toastTimer: Timer?

    var settings = AppSettings()
    /// 裁曲页异步裁曲期间持有，防止 Cutter 被释放导致回调断掉
    var activeCutter: Cutter?
    /// 逐首收卷的在途 Cutter：局部变量 + GCD 块引用在"派发报告的同一毫秒"就会断气，
    /// 排队中的主队列回调块会拿到 nil 静默蒸发（行永远卡住）。控制器自己持有，onAllDone 时释放。
    private var activeCutters: [Cutter] = []
    private var capture = AudioCapture()
    private var monitor = NowPlayingMonitor()
    private let artworkColor = ArtworkColorService()
    /// 上一次交给封面管线的 key：用于在切到无封面曲目时一次性清空旧氛围（避免逐拍闪断）
    private var accentKey: String?
    /// 上一次封面字节的内容签名：字节未变时不重建 NSImage，避免逐拍交叉淡入
    private var lastArtworkSignature: String?
    private var timeline: [TimelineEntry] = []
    private var sessionDir: URL?
    private var tickTimer: Timer?
    private var rowID = 0
    private var subscribers = Set<AnyCancellable>()

    // 挂机监听状态
    private var bgTimer: Timer?
    private var bgBusy = false
    private var bgLastElapsed: Double = -1
    private var bgStallSince: Date?

    // 逐首录制状态（切歌即分文件，一首一收卷）
    private var songIndex = 0                     // 当前文件序号（song-001…）
    private var songFileURL: URL?                 // 当前正在写的 WAV
    private var pendingEntries: [TimelineEntry] = []   // 当前文件内的时间轴（换文件失败时同文件多首）
    private var pendingRowIDs: [Int] = []         // 与 pendingEntries 对应的行号（编码完成后回填状态）
    private var songStartElapsed = 0.0            // 当前歌在会话内的起始秒（歌词推进用）
    private var songLeadSeconds = 0.0             // 确认前歌已播的秒数（候选首见→确认的差值；进度显示用——歌不是从确认瞬间才开始的）
    // 确认器（核心设计：歌名必须连续稳定出现才确认，确认之前不做任何不可逆操作）
    private var currentStableTitle = ""           // 已确认正在采录的歌名
    private var pendingTitle = ""                 // 观察中的候选歌名（可能是一拍即逝的切歌抖动）
    private var pendingStableCount = 0            // 候选连续稳定出现的拍数
    private var pendingFirstSeenAt: Date?         // 候选第一次见到的时刻（账面用）
    private var sessionGen = 0                    // 会话代际：跨场防串（上一场的收卷回调不得写进新场统计）

    @MainActor init(settings: AppSettings) {
        self.settings = settings
        // 挂机监听开关：设置页 / 菜单栏任一处改动都同步到这里
        settings.$backgroundMonitor
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] on in self?.setBackgroundMonitor(on) }
            .store(in: &subscribers)
        // 无声自动停：录制中途改开关也要实时生效（阈值 60 秒）
        settings.$silenceAutoStop
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] on in
                guard let self, self.state == .live else { return }
                self.capture.silenceLimit = on ? 60.0 : .infinity
            }
            .store(in: &subscribers)
        refreshLibrary()
        startRouteWatcher()
        Notifier.requestAuthorization()
    }

    // MARK: 采诗通道状态实时监测
    // 设备列表 / 默认输出一变（比如用户在音频 MIDI 设置手工建好多输出设备）就刷新，红字实时变绿
    private func startRouteWatcher() {
        AudioRouting.startWatching { [weak self] in
            // HAL 回调会成串触发，去抖 0.6s 再刷新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.refreshRouteStatus()
            }
        }
    }

    /// 轻量刷新路由相关状态（不动 channel/encoder，避免全量自检的闪烁）
    func refreshRouteStatus() {
        let routed = AudioRouting.isDefaultOutputRouted()
        routeReady = routed
        setEnv("route", routed ? .ok : .fail, note: routed ? "" : "未接通")
        if AudioCapture.findBlackHole() != nil {
            setEnv("blackhole", .ok)
        } else {
            setEnv("blackhole", .fail, note: "未安装")
        }
    }

    // MARK: 采诗通道（多输出设备）一键接通
    func setupAudioRoute() {
        showToast("正在创建采诗通道…")
        DispatchQueue.global().async { [weak self] in
            do {
                let changed = try AudioRouting.setupRoute()
                let routed = AudioRouting.isDefaultOutputRouted()
                DispatchQueue.main.async {
                    self?.routeReady = routed
                    self?.showToast(changed ? "采诗通道已接通，边听边录" : "采诗通道已是默认输出")
                    self?.runEnvCheck()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.showToast("接通失败：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: 环境自检
    func runEnvCheck() {
        for i in envChecks.indices { envChecks[i].status = .checking; envChecks[i].note = "" }
        // Sendable 域检查兼容（Swift 5.10+）：@Sendable 闭包不许捕获 weak var self，
        // 统一先落成 let 引用再进 Task
        // BlackHole
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let box = self
            Task { @MainActor in
                if AudioCapture.findBlackHole() != nil {
                    box?.setEnv("blackhole", .ok)
                } else {
                    box?.setEnv("blackhole", .fail, note: "未安装")
                }
            }
        }
        // 采诗通道（正在播放）
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.45) { [weak self] in
            let info = NowPlayingMonitor.fetch()
            let box = self
            Task { @MainActor in
                if info != nil { box?.setEnv("channel", .ok) }
                else { box?.setEnv("channel", .fail, note: "拿不到正在播放") }
            }
        }
        // MP3 编码器
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.75) { [weak self] in
            let box = self
            Task { @MainActor in
                if LameEncoder.available() { box?.setEnv("encoder", .ok) }
                else { box?.setEnv("encoder", .fail, note: "缺 LAME，将回落 M4A") }
            }
        }
        // 采诗通道（默认输出是否进 BlackHole）
        routeReady = AudioRouting.isDefaultOutputRouted()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.05) { [weak self] in
            let box = self
            Task { @MainActor in
                let ok = AudioRouting.isDefaultOutputRouted()
                box?.routeReady = ok
                if ok { box?.setEnv("route", .ok) }
                else { box?.setEnv("route", .fail, note: "未接通") }
            }
        }
    }

    private func setEnv(_ id: String, _ s: EnvCheck.Status, note: String = "") {
        if let i = envChecks.firstIndex(where: { $0.id == id }) {
            envChecks[i].status = s
            envChecks[i].note = note
        }
    }

    // MARK: 开始采诗
    func startSession() {
        // 环境不合格先引导
        if envChecks.first(where: { $0.id == "blackhole" })?.status != .ok {
            runEnvCheck()
            showToast("先通过环境自检，再开始采诗")
            return
        }
        let out = settings.resolvedOutputDir
        let day = out.appendingPathComponent(dayString())
        let sess = day.appendingPathComponent("session-" + timeString())
        try? FileManager.default.createDirectory(at: sess, withIntermediateDirectories: true)
        sweepOrphanSessionDirs(in: day)
        sessionDir = sess
        // 逐首录制：切歌即换文件，一首一收卷（不再集中大 WAV + 事后裁曲）
        // songIndex = 当前文件的序号；首个文件 song-001，切歌后从 song-002 起（避免自换自）
        songIndex = 1
        songFileURL = sess.appendingPathComponent("song-001.wav")
        pendingEntries = []
        pendingRowIDs = []
        songStartElapsed = 0
        currentStableTitle = ""
        pendingTitle = ""
        pendingStableCount = 0
        pendingFirstSeenAt = nil
        sessionGen += 1
        Diag.log("SC startSession gen=\(sessionGen)")
        // 行号不复位：跨会话持续递增，保证全局唯一——
        // 收卷回调按行号回填，即使代际翻转（挂机自动重开等）也绝不可能写错行
        trackRows = []
        timeline = []
        doneStats = DoneStats()
        cutTasks = []
        elapsed = 0
        coverAccent = nil
        lyrics = LyricsDocument(lines: [])
        lyricIndex = -1

        // 无声自动停：阈值 60 秒（歌间串场/掌声/电台 DJ 静音都不会误触发；真停播由挂机监听的停播判定负责）
        capture.silenceLimit = settings.silenceAutoStop ? 60.0 : .infinity
        capture.onLevel = { [weak self] level in self?.meter.push(level) }
        capture.onSilence = { [weak self] in
            Task { @MainActor in
                self?.showToast("检测到静音，自动收卷")
                self?.stopAndCut()
            }
        }
        do {
            try capture.start(outputURL: songFileURL!)
        } catch {
            showToast("开录失败：\(error.localizedDescription)")
            return
        }

        // 正在播放监听 —— 确认驱动设计：
        // 监听层每拍只喂确认器；歌名要连续稳定 2 拍相同才被「确认」为新歌，
        // 确认之前不做任何不可逆操作（不入列、不换文件、不收卷）。
        // 切歌瞬间 A→B→A→B 的抖动一拍即逝，永远到不了确认线；B 稳定后才一次性顺序执行收卷+换文件+入列。
        monitor.onUpdate = { [weak self] info in
            Task { @MainActor in
                guard let self, let info, !info.title.isEmpty else { return }
                self.currentTrack = info                       // 头部卡片实时（候选也预览）
                self.updateArtwork(info)

                if info.title == self.currentStableTitle {
                    // 已确认的歌：歌手/专辑/时长/封面纠正 → 只更新，永不触发流程
                    self.pendingTitle = ""
                    self.pendingStableCount = 0
                    self.applyMetaCorrection(info)
                } else if info.title == self.pendingTitle {
                    // 候选再稳定一拍
                    self.pendingStableCount += 1
                    if self.pendingStableCount >= 2 {
                        self.confirmTrack(info)
                    }
                } else {
                    // 新候选进入观察（先不动任何状态）
                    self.pendingTitle = info.title
                    self.pendingStableCount = 1
                    self.pendingFirstSeenAt = Date()
                }
            }
        }
        monitor.start()

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let box = self
            Task { @MainActor in
                guard let box, box.state == .live else { return }
                box.elapsed += 1
                // 歌词行推进（按本歌在会话内的起始秒推算）
                if let t = box.currentTrack, box.elapsed > 0 {
                    // 与 RecordView.songPos 同一时间基准（含确认前已播的头），否则逐字高亮会比行早跳 ~songLeadSeconds
                    let offset = box.elapsed - box.songStartElapsed + box.songLeadSeconds
                    if offset >= 0, !box.lyrics.lines.isEmpty {
                        box.lyricIndex = box.lyrics.currentLineIndex(at: offset)
                    }
                }
            }
        }

        state = .live
        showToast("开始采诗，府中已有的歌会自动跳过")
    }

    // MARK: 确认新歌（确认器达到稳定线后调用，单次顺序执行；无任何去重/残影守卫——确认器天然去抖）
    private func confirmTrack(_ info: TrackInfo) {
        // 记账：候选首见→确认的差值 = 确认前歌已播的头（拍间隔 1s + 确认线 2 拍 ≈ 1.5~2.5s）
        songLeadSeconds = pendingFirstSeenAt.map { min(5, max(0, Date().timeIntervalSince($0))) } ?? 0
        currentStableTitle = info.title
        pendingTitle = ""
        pendingStableCount = 0
        Diag.log("SC confirmTrack 「\(info.title)」")

        // ① 定格旧行：采录中 → 收卷中（此刻新行还没入列，不会误伤）
        for i in trackRows.indices where trackRows[i].status == .recording {
            trackRows[i].status = .pending
            trackRows[i].stageLabel = "收卷中…"
        }

        // ② 新行入列（库中已有 → 跳过徽章）
        let exists = Self.existsInLibrary(name: info.title, dir: settings.resolvedOutputDir)
        rowID += 1
        // 本场第一首歌 = 半路接入：录制起点落在歌的中途（挂机半路拉起 / 用户中途点开始），
        // 汽水不暴露播放位置，绝对进度不可知——行内进度显示 --:--
        trackRows.append(TrackRow(id: rowID, title: info.title, artist: info.artist, album: info.album,
                                  status: exists ? .skipped : .recording,
                                  artwork: info.artwork.flatMap { NSImage(data: $0) },
                                  midJoin: pendingEntries.isEmpty))

        // ③ 换文件 + 收卷上一文件（首首歌沿用开录建好的 song-001，不换）
        let rotate = !pendingEntries.isEmpty
        var startT = 0.0
        if rotate {
            songIndex += 1
            if let sdir = sessionDir {
                let newURL = sdir.appendingPathComponent(String(format: "song-%03d.wav", songIndex))
                do {
                    let prevFile = songFileURL
                    let prevEntries = pendingEntries
                    let prevRowIDs = pendingRowIDs
                    try capture.rotate(to: newURL)
                    songFileURL = newURL
                    pendingEntries = []
                    pendingRowIDs = []
                    if !prevEntries.isEmpty, let file = prevFile {
                        Diag.log("SC rotate 成功 → 收卷 \(file.lastPathComponent)")
                        finalizeFile(file, entries: prevEntries, rowIDs: prevRowIDs)
                    }
                } catch {
                    // 换文件失败：本首并入当前文件，从实际位置起切
                    Diag.log("SC rotate 失败：\(error.localizedDescription)")
                    showToast("换文件失败，本首并入上一文件：\(error.localizedDescription)")
                    startT = capture.recordedSeconds
                }
            } else {
                Diag.log("SC rotate 跳过：sessionDir 缺失（不应发生），本首并入当前文件")
                startT = capture.recordedSeconds
            }
        }
        // ④ 打点：正常 t=0（确认时刻起 B 在新文件从头写，完整；B 已播的头 ~2 秒留在上一文件尾部）
        let entry = TimelineEntry(t: startT,
                                  title: info.title, artist: info.artist,
                                  album: info.album, duration: info.duration,
                                  cover: info.artwork)
        pendingEntries.append(entry)
        pendingRowIDs.append(rowID)
        songStartElapsed = elapsed

        // 歌词预取：始终走同一条路。fetchDocument 先读汽水本地 KRC（零联网、可逐字），
        // 再退回本地缓存 / 在线源——离线用户也能拿到本地 KRC 逐字时间轴。
        // 抓到就设置、抓不到就清空，绝不让上一首的歌词残留。
        let dur = info.duration
        let cacheDir = settings.resolvedOutputDir.appendingPathComponent(".lyrics")
        let offline = settings.offlineMode
        let fallback = settings.lyricFallback
        Task {
            let doc = await LyricsFetcher.fetchDocument(title: info.title, artist: info.artist,
                                                         duration: dur, offline: offline,
                                                         fallback: fallback, cacheDir: cacheDir)
            await MainActor.run {
                self.lyrics = doc ?? LyricsDocument(lines: [])
                self.lyricIndex = -1
            }
        }
    }

    /// 封面字节的内容签名（长度 + FNV-1a 64 位）。不用 Swift 的 hashValue：
    /// 每次进程启动都会随机化，无法稳定表达"同一张图"。
    private static func artworkSignature(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "\(data.count)-\(String(hash, radix: 16))"
    }

    // MARK: 封面入口：更新头部封面并异步派生强调色（灰阶/低饱和回落 nil）
    private func updateArtwork(_ info: TrackInfo) {
        guard let art = info.artwork, let img = NSImage(data: art) else {
            // 无封面：切到新 key 时回落默认氛围（同 key 重复回调不重复清，避免逐拍闪断）
            if accentKey != info.key {
                accentKey = info.key
                artworkImage = nil
                lastArtworkSignature = nil
                coverAccent = nil
            }
            return
        }
        accentKey = info.key
        let signature = Self.artworkSignature(art)
        // 仅当封面字节真正变化时才替换 NSImage；同图逐拍回调复用旧对象，
        // 否则 SwiftUI 每秒都认为封面变了而重复交叉淡入。
        if signature != lastArtworkSignature {
            lastArtworkSignature = signature
            artworkImage = img
        }
        let key = info.key
        // 强调色按图像签名缓存：同 key 晚到的不同封面各自派生，正负缓存都不会互相压制。
        artworkColor.accent(forImage: img, signature: signature) { [weak self] color in
            guard let self, self.currentTrack?.key == key else { return }
            self.coverAccent = color.map { Color(nsColor: $0) }
        }
    }

    // MARK: 更新器：已确认歌的元信息纠正（歌手/专辑/时长/封面晚到）→ 只原地更新，永不触发任何流程
    private func applyMetaCorrection(_ info: TrackInfo) {
        if !pendingEntries.isEmpty, pendingEntries[pendingEntries.count - 1].title == info.title {
            let old = pendingEntries[pendingEntries.count - 1]
            pendingEntries[pendingEntries.count - 1] = TimelineEntry(
                t: old.t,
                title: old.title,
                artist: info.artist,
                album: info.album,
                duration: info.duration > 0 ? info.duration : old.duration,
                cover: old.cover ?? info.artwork
            )
        }
        if let i = trackRows.lastIndex(where: { $0.title == info.title && $0.status == .recording }) {
            trackRows[i].artist = info.artist
            trackRows[i].album = info.album
            if trackRows[i].artwork == nil, let art = info.artwork {
                trackRows[i].artwork = NSImage(data: art)
            }
        }
        // 封面晚到（已确认歌）：这里只回填行缩略图；
        // 头部封面/强调色由 onUpdate 的 updateArtwork(info) 统一负责，
        // 用同一份 info 再调一次会重复入队（且刷新 lastArtworkSignature 时序）。
    }

    private static func existsInLibrary(name: String, dir: URL) -> Bool {
        // 与 Cutter 的落盘目录一致（当日日期子目录），顶层扫描会漏判 → 行先入列"采录中"再被流水线跳过
        let fm = FileManager.default
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let out = dir.appendingPathComponent(f.string(from: Date()))
        guard let files = try? fm.contentsOfDirectory(atPath: out.path) else { return false }
        return files.contains { $0.contains(name) && !$0.hasSuffix(".lrc") }
    }

    // MARK: 下一阕（真正让汽水切到下一首；换歌后监听会自动在时间轴上打新点）
    func nextTrack() {
        guard state == .live else { return }
        let ok = NowPlayingControl.next()
        if ok {
            showToast("已切下一阕")
        } else {
            showToast("切歌失败：没找到汽水的控制通道")
        }
    }

    // MARK: 收卷（停录 + 当前文件交给后台流水线；无集中裁曲，逐首早已收卷）
    func stopAndCut() {
        guard state == .live else { return }
        state = .done
        monitor.stop()
        tickTimer?.invalidate()
        capture.stop()
        meter.reset()

        if let last = trackRows.last, last.status == .recording {
            trackRows[trackRows.count - 1].status = .pending
            trackRows[trackRows.count - 1].stageLabel = "收卷中…"
        }

        // 当前文件的尾首交给流水线（之前每首在切歌瞬间已各自收卷）
        if !pendingEntries.isEmpty, let file = songFileURL {
            Diag.log("SC stopAndCut → 收卷尾首 \(file.lastPathComponent) entries=\(pendingEntries.count)")
            finalizeFile(file, entries: pendingEntries, rowIDs: pendingRowIDs)
        } else if let file = songFileURL {
            // 没打过任何点（汽水没播/候选全被确认器滤掉）：录音无从裁切，进废纸篓可反悔
            Diag.log("SC stopAndCut 无时间轴，录音进废纸篓 \(file.lastPathComponent)")
            LefuTrash.trash(file)
            songFileURL = nil
        }
        pendingEntries = []
        pendingRowIDs = []
        tryCleanupSessionDir()
        refreshLibrary()
    }

    // MARK: 单文件后台收卷：完整复用 Cutter 流水线（过短丢弃/静音跳过/编码/签章/歌词后补/库中已有跳过）
    private func finalizeFile(_ file: URL, entries: [TimelineEntry], rowIDs: [Int]) {
        let gen = sessionGen
        Diag.log("SC finalizeFile \(file.lastPathComponent) gen=\(gen) rowIDs=\(rowIDs) 标题=\(entries.map(\.title))")
        let bytesPerSecond = capture.pcmBytesPerSecond
        let out = settings.resolvedOutputDir.appendingPathComponent(dayString())
        let cutter = Cutter(wavURL: file, outDir: out, settings: settings)
        activeCutters.append(cutter)   // 双保险：控制器持有在途流水线
        // 本首所在录音 WAV 记到行上（成品未落时点击行可先定位录音）
        for rid in rowIDs {
            if let r = trackRows.firstIndex(where: { $0.id == rid }) { trackRows[r].wavPath = file.path }
        }
        // 行内进度：每首歌的工序实时写回会话队列行，MP3 落盘即刷右栏
        // 关键设计：行状态回填不做代际拦截——行号全局唯一，按行号写永远写不串行；
        // 任何 guard 静默 return 都会让行永远停在「收卷中」（已踩坑），这里宁可多写也不吞回调。
        cutter.onTaskUpdate = { [weak self] task in
            Task { @MainActor in
                guard let self else { Diag.log("SC onTaskUpdate 到达但 self 已释放 task=\(task.id)"); return }
                guard rowIDs.indices.contains(task.id) else {
                    Diag.log("SC onTaskUpdate 拦截 task=\(task.id) 越界 rowIDs=\(rowIDs.count)")
                    return
                }
                guard let r = self.trackRows.firstIndex(where: { $0.id == rowIDs[task.id] }) else {
                    Diag.log("SC onTaskUpdate 拦截 task=\(task.id) 行未找到 rid=\(rowIDs[task.id]) 现有行=\(self.trackRows.map(\.id))")
                    return
                }
                Diag.log("SC onTaskUpdate 落地 task=\(task.id) stage=\(task.stage) 行=\(rowIDs[task.id]) gen=\(gen)/\(self.sessionGen)")
                self.trackRows[r].stageLabel = task.stageLabel
                switch task.stage {
                case .done:
                    self.trackRows[r].status = .captured
                    self.trackRows[r].outputPath = task.outputPath
                    self.trackRows[r].sizeBytes = task.sizeBytes
                    self.refreshLibrary()
                case .skipped:
                    self.trackRows[r].status = .skipped
                case .queue, .slice, .encode, .tags, .lyrics:
                    self.trackRows[r].status = .processing
                case .failed:
                    break   // 保留处理中状态，stageLabel 显示失败原因（红色）
                }
            }
        }
        cutter.onAllDone = { [weak self, weak cutter] tasks in
            Task { @MainActor in
                guard let self else { Diag.log("SC onAllDone 到达但 self 已释放"); return }
                // 流水线收尾：断回调 + 释放持有（闭包持 weak cutter，无环）
                if let cutter {
                    cutter.onTaskUpdate = nil
                    cutter.onAllDone = nil
                    self.activeCutters.removeAll { $0 === cutter }
                }
                let stale = gen != self.sessionGen   // 代际只管统计数字，不拦行状态回填
                Diag.log("SC onAllDone 到达 tasks=\(tasks.count) stale=\(stale) gen=\(gen)/\(self.sessionGen)")
                // 文件总时长（换算歌曲时长用）
                let fileSize = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value ?? 0
                let fileSeconds = max(0, (Double(fileSize) - 44) / max(1, bytesPerSecond))
                for (i, task) in tasks.enumerated() {
                    let dur = (i + 1 < tasks.count) ? max(0, tasks[i + 1].entry.t - task.entry.t)
                                                    : max(0, fileSeconds - task.entry.t)
                    if !stale {
                        switch task.stage {
                        case .done:
                            self.doneStats.count += 1
                            self.doneStats.sizeBytes += task.sizeBytes
                            self.doneStats.seconds += dur
                            self.doneStats.rows.append(TrackRow(id: 1000 + self.doneStats.rows.count,
                                                                title: task.entry.title, artist: task.entry.artist,
                                                                status: .captured))
                            // 封卷仪式：每首成品落盘即发通知 + 一次轻触感（仅成功统计这一处，避免重复）
                            Notifier.songCaptured(title: task.entry.title, artist: task.entry.artist, cover: task.entry.cover)
                            Notifier.tap()
                        case .skipped:
                            self.doneStats.skippedCount += 1
                        case .failed:
                            self.doneStats.failedCount += 1
                        default: break
                        }
                    }
                    // 行状态终态回填：无条件按行号写（行号全局唯一，跨场也写不串；
                    // 上一场的行多半已被清空，找不到就自然跳过）——这一步是「收卷中」卡死的最终兜底
                    if i < rowIDs.count, let r = self.trackRows.firstIndex(where: { $0.id == rowIDs[i] }) {
                        switch task.stage {
                        case .done:
                            self.trackRows[r].status = .captured
                            self.trackRows[r].sizeBytes = task.sizeBytes
                            self.trackRows[r].seconds = dur
                        case .skipped: self.trackRows[r].status = .skipped
                        case .failed: self.trackRows[r].stageLabel = task.stageLabel
                        default: break
                        }
                    }
                }
                // 文件 WAV 用完即清：成败一律进废纸篓（可反悔）。
                // 裁曲页已退役，失败段没有人工重切的入口，留着只会让 session 目录越积越乱；
                // 废纸篓本身就是反悔通道，真要抢救去那里捞。
                LefuTrash.trash(file)
                if self.songFileURL == file { self.songFileURL = nil }
                self.tryCleanupSessionDir()
                self.refreshLibrary()
            }
        }
        cutter.run(entries: entries)   // 强持有自撑到完成
    }

    // MARK: session 目录管理
    // session 目录只是逐首 WAV 的中转站：每首 WAV 在流水线收尾时已各自进废纸篓，
    // 目录里一个 .wav 都不剩（且已不在录制中）就把目录本身也清掉，不让空壳混在成品旁。

    /// 目录清空即自动清目录（每首 onAllDone 收尾 + stopAndCut 时调用；录制中绝不动目录）
    private func tryCleanupSessionDir() {
        guard let dir = sessionDir, state != .live else { return }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: dir.path),
           files.contains(where: { $0.hasSuffix(".wav") }) {
            return   // 还有在途流水线没消化的 WAV，等它们收完再清
        }
        LefuTrash.trash(dir)
        Diag.log("SC session 目录已清 \(dir.lastPathComponent)")
        sessionDir = nil
    }

    /// 开新场时顺手清掉旧的空 session 目录（App 被杀/崩溃留下的孤儿；全部废纸篓可反悔）
    private func sweepOrphanSessionDirs(in day: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: day.path) else { return }
        for f in entries where f.hasPrefix("session-") {
            let u = day.appendingPathComponent(f)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = (try? fm.contentsOfDirectory(atPath: u.path)) ?? []
            guard !files.contains(where: { $0.hasSuffix(".wav") }) else { continue }
            LefuTrash.trash(u)
            Diag.log("SC 清掉孤儿 session 目录 \(f)")
        }
    }

    // MARK: 返回首页
    func reset() {
        sessionGen += 1   // 作废在途收卷回调
        Diag.log("SC reset gen=\(sessionGen)")
        trackRows = []
        cutTasks = []
        doneStats = DoneStats()
        elapsed = 0
        currentTrack = nil
        artworkImage = nil
        coverAccent = nil
        lyrics = LyricsDocument(lines: [])
        lyricIndex = -1
        // 清空封面签名/钥匙，避免下一场首曲与上一场尾曲字节相同时跳过重建封面
        lastArtworkSignature = nil
        accentKey = nil
        state = .idle
        runEnvCheck()
        refreshLibrary()
    }

    func openOutputFolder() {
        let dir = settings.resolvedOutputDir.appendingPathComponent(dayString())
        NSWorkspace.shared.open(dir)
    }

    // MARK: BlackHole 一键安装（全新机器零环境）
    func installBlackHole() {
        guard !installingBlackHole else { return }
        installingBlackHole = true
        showToast("正在下载 BlackHole…")
        Task {
            do {
                let pkg = try await BlackHoleInstaller.download()
                await MainActor.run { self.showToast("下载完成，请在弹出的密码框授权安装") }
                try BlackHoleInstaller.install(pkg: pkg)
                try? FileManager.default.removeItem(at: pkg)
                let ok = await BlackHoleInstaller.verifyAfterDelay()
                await MainActor.run {
                    self.installingBlackHole = false
                    if ok {
                        self.showToast("BlackHole 已装好，环境自检中")
                        self.runEnvCheck()
                    } else {
                        self.showToast("已安装但未枚举到驱动，试试重启汽水音乐")
                        self.runEnvCheck()
                    }
                }
            } catch {
                await MainActor.run {
                    self.installingBlackHole = false
                    self.showToast("安装未完成：\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: 府库扫描（今日成果 + 最近成品，供待机页右栏）
    func refreshLibrary() {
        let dir = settings.resolvedOutputDir
        // 上一次的封面按 id 存档：本次重建时直接继承，刷新瞬间封面墙不再集体变白
        var previousCovers: [URL: NSImage] = [:]
        for item in library.all {
            if let cover = item.cover { previousCovers[item.id] = cover }
        }
        DispatchQueue.global().async { [weak self] in
            let fm = FileManager.default
            let audioExt: Set<String> = ["mp3", "m4a", "wav", "flac", "aac"]
            var items: [OutputItem] = []
            func scan(_ url: URL, depth: Int) {
                guard depth <= 2, let entries = try? fm.contentsOfDirectory(atPath: url.path) else { return }
                for f in entries {
                    let u = url.appendingPathComponent(f)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
                    if isDir.boolValue {
                        scan(u, depth: depth + 1)   // 日期目录、session 等子目录
                        continue
                    }
                    let ext = (f as NSString).pathExtension.lowercased()
                    guard audioExt.contains(ext) else { continue }
                    let attr = try? fm.attributesOfItem(atPath: u.path)
                    items.append(OutputItem(
                        id: u,
                        name: (f as NSString).deletingPathExtension,
                        size: (attr?[.size] as? Int64) ?? 0,
                        date: (attr?[.modificationDate] as? Date) ?? .distantPast
                    ))
                }
            }
            scan(dir, depth: 1)
            // 继承已提取过的封面（id 不变即沿用），避免每次刷新清空封面墙
            for i in items.indices {
                if let cover = previousCovers[items[i].id] { items[i].cover = cover }
            }
            items.sort { $0.date > $1.date }
            let cal = Calendar.current
            let todayItems = items.filter { cal.isDateInToday($0.date) }
            let stats = LibraryStats(
                todayCount: todayItems.count,
                todayBytes: todayItems.reduce(0) { $0 + $1.size },
                totalBytes: items.reduce(0) { $0 + $1.size },
                all: items,
                recent: Array(items.prefix(12))
            )
            // Sendable 域检查兼容（Swift 5.10+）：let 引用盒落成，再进 @Sendable Task
            let box = self
            Task { @MainActor in
                guard let s = box else { return }
                // 先一次性落地扫描结果（items 已继承旧封面），封面墙不会闪白
                s.library = stats
                // 只给仍缺封面的 mp3 读 ID3 头（不碰音频数据），在后台线程提取后攒成一批。
                // 旧实现每命中一首就从主线程整体拷贝 s.library 再赋值（O(N²)）且先清空封面；
                // 这里提取期间让出主线程，最终只做一次批量合并赋值。
                let pending = stats.all.filter { $0.cover == nil && $0.id.pathExtension.lowercased() == "mp3" }
                guard !pending.isEmpty else { return }
                let covers: [URL: NSImage] = await withCheckedContinuation { (cont: CheckedContinuation<[URL: NSImage], Never>) in
                    DispatchQueue.global(qos: .utility).async {
                        var found: [URL: NSImage] = [:]
                        for item in pending {
                            if let img = CoverExtractor.extract(from: item.id) { found[item.id] = img }
                        }
                        cont.resume(returning: found)
                    }
                }
                guard !covers.isEmpty else { return }
                var rec = s.library
                var recentIdx: [URL: Int] = [:]
                for (i, it) in rec.recent.enumerated() { recentIdx[it.id] = i }
                var changed = false
                for i in rec.all.indices where rec.all[i].cover == nil {
                    guard let img = covers[rec.all[i].id] else { continue }
                    rec.all[i].cover = img
                    if let ri = recentIdx[rec.all[i].id] { rec.recent[ri].cover = img }
                    changed = true
                }
                if changed { s.library = rec }
            }
        }
    }
    // MARK: Toast（已按需求停用：完成任务的短提示不再显示；保留函数壳便于日后恢复）
    func showToast(_ s: String) {
        // toast = s
        // toastTimer?.invalidate()
        // toastTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
        //     Task { @MainActor in self?.toast = nil }
        // }
    }

    // MARK: 挂机监听（菜单栏常驻 · 三期功能）
    // 开启后：检测到汽水开播 → 自动开录；连续停播 → 自动收卷裁曲
    func setBackgroundMonitor(_ on: Bool) {
        if on { startBackgroundMonitor() } else { stopBackgroundMonitor() }
    }

    private func startBackgroundMonitor() {
        guard bgTimer == nil else { return }
        bgStallSince = nil
        bgLastElapsed = -1
        bgTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            let box = self
            Task { @MainActor in box?.bgPoll() }
        }
        showToast("挂机监听已开启：开播自动采诗")
    }

    private func stopBackgroundMonitor() {
        bgTimer?.invalidate()
        bgTimer = nil
    }

    private func bgPoll() {
        guard bgTimer != nil, !bgBusy else { return }
        bgBusy = true
        // fetch 最长阻塞 0.8s，放后台线程，避免卡主线程
        DispatchQueue.global().async { [weak self] in
            let info = NowPlayingMonitor.fetch()
            let box = self
            Task { @MainActor in
                box?.bgBusy = false
                box?.bgHandle(info)
            }
        }
    }

    private func bgHandle(_ info: TrackInfo?) {
        switch state {
        case .idle, .done:
            guard let info,
                  envChecks.first(where: { $0.id == "blackhole" })?.status == .ok else { break }
            // 必须确认真的在播才自动开录（汽水暂停时 info 仍非空）
            if bgIsPlaying(info) {
                bgLastElapsed = -1
                bgStallSince = nil
                showToast("挂机监听：检测到开播，自动采诗")
                startSession()
            }
        case .live:
            let playing = info.map(bgIsPlaying) ?? false
            if playing {
                bgStallSince = nil
            } else {
                if bgStallSince == nil {
                    bgStallSince = Date()
                } else if Date().timeIntervalSince(bgStallSince!) >= 6 {
                    bgStallSince = nil
                    showToast("挂机监听：停播自动收卷")
                    stopAndCut()
                }
            }
        case .cutting:
            break
        }
    }

    /// 是否真的在播：优先 PlaybackRate（汽水的 elapsed 恒为 0，不可用）；字段缺失才退回进度判断
    private func bgIsPlaying(_ info: TrackInfo) -> Bool {
        if let r = info.rate { return r > 0 }
        let advancing = info.elapsed > bgLastElapsed + 0.05
        bgLastElapsed = info.elapsed
        return advancing
    }

    // MARK: 时间格式
    private func dayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    private func timeString() -> String {
        let f = DateFormatter(); f.dateFormat = "HHmmss"
        return f.string(from: Date())
    }
    var elapsedText: String {
        let h = Int(elapsed) / 3600, m = Int(elapsed) % 3600 / 60, s = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    /// 当前歌已播放的秒数 = 本歌采录时长 + 确认前已播的头（进度显示用）
    var songOffset: Double { max(0, elapsed - songStartElapsed + songLeadSeconds) }
}

// MARK: - MP3 内嵌封面提取（配套 ID3Writer 的 v2.3，兼容 v2.4）
enum CoverExtractor {
    static func extract(from url: URL) -> NSImage? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        let head = fh.readData(ofLength: 10)
        let b = [UInt8](head)
        guard b.count >= 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 else { return nil } // "ID3"
        let version = b[3]
        let tagSize = (Int(b[6]) << 21) | (Int(b[7]) << 14) | (Int(b[8]) << 7) | Int(b[9]) // synchsafe
        let data = fh.readData(ofLength: min(tagSize, 1 << 20)) // 最多 1MB，封面必在前段
        var i = 0
        while i + 10 <= data.count {
            guard let fid = String(bytes: data[i..<i + 4], encoding: .ascii),
                  fid.allSatisfy({ ($0.isUppercase && $0.isLetter) || $0.isNumber }) else { break } // TIT2/APIC 等含数字
            let fsize: Int
            if version >= 4 { // v2.4 synchsafe
                fsize = (Int(data[i + 4]) << 21) | (Int(data[i + 5]) << 14) | (Int(data[i + 6]) << 7) | Int(data[i + 7])
            } else {          // v2.3 普通大端
                fsize = (Int(data[i + 4]) << 24) | (Int(data[i + 5]) << 16) | (Int(data[i + 6]) << 8) | Int(data[i + 7])
            }
            let bodyStart = i + 10
            guard fsize > 0, bodyStart + fsize <= data.count else { break }
            if fid == "APIC" {
                let end = bodyStart + fsize
                var p = bodyStart
                let enc = data[p]; p += 1
                while p < end && data[p] != 0 { p += 1 }     // MIME 到 \0
                p += 1
                p += 1                                       // picture type
                if enc == 1 || enc == 2 {                    // UTF-16 desc，双 \0 结尾
                    while p + 1 < end && !(data[p] == 0 && data[p + 1] == 0) { p += 2 }
                    p += 2
                } else {                                     // latin/UTF-8 desc，单 \0 结尾
                    while p < end && data[p] != 0 { p += 1 }
                    p += 1
                }
                guard p < end - 100 else { break }
                let img = data.subdata(in: p..<end)
                if let nsimg = NSImage(data: img) { return nsimg }
                break
            }
            i = bodyStart + fsize
        }
        return nil
    }
}
