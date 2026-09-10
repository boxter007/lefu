import Foundation
import AVFoundation

// MARK: - 时间轴条目
struct TimelineEntry: Codable {
    let t: Double          // 会话内起始秒
    let title: String
    let artist: String
    let album: String
    let duration: Double   // 元信息时长（0 未知）
    var cover: Data? = nil // 曲目封面（PNG/JPEG 原始数据，旧 jsonl 无此字段也不影响解码）
}

// MARK: - 裁曲任务状态
struct CutTask: Identifiable {
    enum Stage { case queue, slice, lyrics, encode, tags, done, skipped, failed }
    let id: Int
    var entry: TimelineEntry
    var stage: Stage = .queue
    var stageLabel: String = "排队中"
    var outputPath: String?
    var sizeBytes: Int64 = 0
}

// MARK: - 裁曲器
final class Cutter {
    // 进度回调（主线程）
    var onTaskUpdate: ((CutTask) -> Void)?
    var onAllDone: (([CutTask]) -> Void)?

    private let wavURL: URL
    private let outDir: URL
    private let settings: AppSettings

    init(wavURL: URL, outDir: URL, settings: AppSettings) {
        self.wavURL = wavURL
        self.outDir = outDir
        self.settings = settings
    }

    func run(entries: [TimelineEntry]) {
        // 强持有 self：异步块自己撑到裁曲完成，防止调用方局部变量释放导致静默中断
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            Diag.log("CUT run 开始 \(wavURL.lastPathComponent) entries=\(entries.count) 首标题=\(entries.first?.title ?? "-")")
            let t0 = Date()
            // 先探测真实录音总长，避免最后一段用元数据时长误判
            parseHeaderIfNeeded()
            let total: Double? = self.wavDataSize > 0
                ? Double(self.wavDataSize) / (self.wavSampleRate * Double(self.wavChannels) * 2)
                : nil
            Diag.log("CUT run 头解析完毕 total=\(total.map { String(format: "%.1fs", $0) } ?? "nil") \(Diag.since(t0))")
            var tasks: [CutTask] = []
            for (i, e) in entries.enumerated() {
                var task = CutTask(id: i, entry: e)
                Diag.log("CUT [\([i])] 排队 title=\(e.title) t=\(e.t)")
                self.report(task)
                do {
                    let end = (i + 1 < entries.count) ? entries[i + 1].t : total
                    task = try self.cut(task, start: e.t, end: end)
                } catch {
                    task.stage = .failed
                    task.stageLabel = "失败：\(error.localizedDescription)"
                    Diag.log("CUT [\([i])] 失败 \(error.localizedDescription)")
                    self.report(task)
                }
                Diag.log("CUT [\([i])] 单首结束 stage=\(task.stage) \(Diag.since(t0))")
                tasks.append(task)
            }
            let finished = tasks
            Diag.log("CUT run 全部完成，派发 onAllDone tasks=\(finished.count)")
            // 同 report：强持有，防止派发瞬间 self 被释放导致收尾回调蒸发
            DispatchQueue.main.async { self.onAllDone?(finished) }
        }
    }

    private func report(_ t: CutTask) {
        let copy = t
        // 强持有 self：主队列块自己撑着 Cutter，直到报告真正落地。
        // （用 [weak self] 时，GCD 跑块一结束 Cutter 即被释放，排队中的主队列报告块跑到时 self 已是 nil → 回调静默蒸发 → 行永远卡住。已踩坑。）
        DispatchQueue.main.async { self.onTaskUpdate?(copy) }
    }

    // MARK: 单首裁切流水线：切段 → 歌词 → 编码 → 标签
    private func cut(_ taskIn: CutTask, start: Double, end: Double?) throws -> CutTask {
        var task = taskIn
        let tCut = Date()
        let dur = (end ?? -1) - start
        let effective = dur > 0 ? dur : (task.entry.duration > 0 ? task.entry.duration : 0)
        if effective > 0 && effective < Double(settings.minLength) {
            task.stage = .skipped
            task.stageLabel = "过短 · 丢弃"
            Diag.log("CUT [\(task.id)] 跳过 过短 effective=\(String(format: "%.1f", effective))s < \(settings.minLength)s")
            report(task)
            return task
        }

        // 切段
        task.stage = .slice
        task.stageLabel = "切段中…"
        report(task)
        Diag.log("CUT [\(task.id)] 切段开始 start=\(String(format: "%.1f", start)) end=\(end.map { String(format: "%.1f", $0) } ?? "nil")")
        let tSlice = Date()
        let pcm = try readSegment(start: start, end: end)
        Diag.log("CUT [\(task.id)] 切段完毕 samples=\(pcm.count) \(Diag.since(tSlice))")

        // 纯静音段：峰值 < 110（满幅 32767 约 -50dB）视为没在放歌
        var peak = 0
        for s in pcm {
            let v = s < 0 ? -Int(s) : Int(s)
            if v > peak { peak = v }
        }
        if peak < 110 {
            task.stage = .skipped
            task.stageLabel = "纯静音 · 跳过"
            Diag.log("CUT [\(task.id)] 跳过 纯静音 peak=\(peak)")
            report(task)
            return task
        }

        // 编码（先出音频文件，歌词后补——歌词只进 .lrc 旁挂，不卡出片）
        task.stage = .encode
        task.stageLabel = "编码中…"
        report(task)

        let safeName = Self.safeFileName("\(task.entry.artist) - \(task.entry.title)")
        if !FileManager.default.fileExists(atPath: outDir.path) {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        }
        let outURL = outDir.appendingPathComponent(safeName + "." + settings.format.ext)

        // 库中已有 → 跳过
        if FileManager.default.fileExists(atPath: outURL.path) {
            task.stage = .skipped
            task.stageLabel = "库中已有 · 跳过"
            Diag.log("CUT [\(task.id)] 跳过 库中已有 \(outURL.lastPathComponent)")
            report(task)
            return task
        }

        var audioData: Data?
        switch settings.format {
        case .wav:
            audioData = Self.wavWrap(pcm: pcm, sampleRate: wavSampleRate, channels: wavChannels)
        case .mp3:
            Diag.log("CUT [\(task.id)] LAME 编码开始 samples=\(pcm.count)")
            let tEnc = Date()
            audioData = LameEncoder.encode(samples: pcm, sampleRate: wavSampleRate, channels: wavChannels)
            Diag.log("CUT [\(task.id)] LAME 编码完毕 out=\(audioData?.count ?? 0)B \(Diag.since(tEnc))")
            if audioData == nil { throw NSError(domain: "Cutter", code: 10, userInfo: [NSLocalizedDescriptionKey: "LAME 编码器不可用"]) }
        case .m4a:
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            try encodeM4A(samples: pcm, sampleRate: wavSampleRate, channels: wavChannels, outURL: tmp)
            audioData = try Data(contentsOf: tmp)
            try? FileManager.default.removeItem(at: tmp)
        }

        // 标签（MP3 内嵌 ID3；其余存 sidecar）
        task.stage = .tags
        task.stageLabel = "标签中…"
        report(task)

        let tTags = Date()
        if settings.format == .mp3, let mp3 = audioData {
            let tag = ID3Writer.tag(title: task.entry.title, artist: task.entry.artist,
                                    album: task.entry.album, coverData: task.entry.cover)
            try (tag + mp3).write(to: outURL)
        } else {
            try audioData?.write(to: outURL)
        }
        Diag.log("CUT [\(task.id)] 写盘完毕 \(outURL.lastPathComponent) \(Diag.since(tTags))")

        // 歌词（MP3 已落盘，这里只补 .lrc 旁挂；联网失败不耽误出片）
        task.stage = .lyrics
        task.stageLabel = "歌词中…"
        report(task)
        var lrcData: String?
        if !settings.offlineMode || settings.lyricFallback {
            // 有界等待：歌词是旁挂非命脉，最多等 8 秒；抓取挂住也不能让出片卡死（曾出现行永远转圈）
            let sema = DispatchSemaphore(value: 0)
            let offline = settings.offlineMode
            let fb = settings.lyricFallback
            let cacheDir = settings.resolvedOutputDir.appendingPathComponent(".lyrics")
            let tLrc = Date()
            // Sendable 域检查兼容（Swift 5.10+）：@Sendable 闭包不许捕获可变局部变量，
            // 用 let 快照 + final class 引用盒传值
            let entryTitle = task.entry.title
            let entryArtist = task.entry.artist
            let entryId = task.id
            final class RefBox { var value: String? = nil }
            let box = RefBox()
            Task {
                box.value = await LyricsFetcher.fetchLRC(
                    title: entryTitle, artist: entryArtist,
                    duration: effective, offline: offline, fallback: fb, cacheDir: cacheDir)
                Diag.log("CUT [\(entryId)] 歌词抓取返回 got=\(box.value != nil) \(Diag.since(tLrc))")
                sema.signal()
            }
            let timedOut = sema.wait(timeout: .now() + 8) == .timedOut
            Diag.log("CUT [\(entryId)] 歌词等待结束 timedOut=\(timedOut) \(Diag.since(tLrc))")
            lrcData = box.value
        }
        if let lrc = lrcData {
            try? lrc.write(to: outDir.appendingPathComponent(safeName + ".lrc"), atomically: true, encoding: .utf8)
        }

        task.stage = .done
        task.stageLabel = "✓ 完成"
        task.outputPath = outURL.path
        task.sizeBytes = ((try? FileManager.default.attributesOfItem(atPath: outURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
        Diag.log("CUT [\(task.id)] ✓ 完成 size=\(task.sizeBytes)B 单首总耗时 \(Diag.since(tCut))")
        report(task)
        return task
    }

    /// M4A：AVAudioFile 原生 AAC 编码（写文件后读回）
    func encodeM4A(samples: [Int16], sampleRate: Double, channels: Int, outURL: URL) throws -> Data {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false) else {
            throw NSError(domain: "Cutter", code: 21, userInfo: [NSLocalizedDescriptionKey: "音频格式构造失败"])
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 256000,
        ]
        let file = try AVAudioFile(forWriting: outURL, settings: settings)
        let chunk = 8192
        var offset = 0
        let totalFrames = samples.count / channels
        while offset < totalFrames {
            let n = min(chunk, totalFrames - offset)
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { continue }
            buf.frameLength = AVAudioFrameCount(n)
            for c in 0..<channels {
                let dst = buf.floatChannelData![c]
                for i in 0..<n {
                    dst[i] = Float(samples[(offset + i) * channels + c]) / 32767.0
                }
            }
            try file.write(from: buf)
            offset += n
        }
        _ = fmt
        return try Data(contentsOf: outURL)
    }

    // MARK: WAV 读取（懒加载文件句柄）
    private var wavFile: FileHandle?
    private var wavSampleRate: Double = 44100
    private var wavChannels: Int = 2
    private var wavDataOffset: UInt64 = 44
    private var wavDataSize: UInt64 = 0
    private var headerParsed = false

    private func parseHeaderIfNeeded() {
        guard !headerParsed, let fh = try? FileHandle(forReadingFrom: wavURL) else { return }
        wavFile = fh
        let head = fh.readData(ofLength: 64)
        if head.count >= 44 {
            let b = [UInt8](head)
            func le32at(_ off: Int) -> UInt32 { UInt32(b[off]) | UInt32(b[off+1]) << 8 | UInt32(b[off+2]) << 16 | UInt32(b[off+3]) << 24 }
            func le16at(_ off: Int) -> UInt16 { UInt16(b[off]) | UInt16(b[off+1]) << 8 }
            wavSampleRate = Double(le32at(24))
            wavChannels = Int(le16at(22))
            // 标准 44 字节头：data 标记在 36
            if head.count >= 44, String(bytes: b[36..<40], encoding: .ascii) == "data" {
                wavDataSize = UInt64(le32at(40))
                wavDataOffset = 44
            }
        }
        headerParsed = true
    }

    private func readSegment(start: Double, end: Double?) throws -> [Int16] {
        parseHeaderIfNeeded()
        guard let fh = wavFile else { throw NSError(domain: "Cutter", code: 3, userInfo: [NSLocalizedDescriptionKey: "录音文件无法读取"]) }
        let bytesPerFrame = wavChannels * 2
        // 饱和运算：起点/终点一律夹在 [wavDataOffset, 文件有效末尾] 内，越界即空段（防 UInt64 下溢崩溃）
        let dataEnd = wavDataOffset + wavDataSize
        let s = (start.isFinite && start > 0) ? start : 0
        let startByte = min(dataEnd, wavDataOffset + UInt64(s * wavSampleRate) * UInt64(bytesPerFrame))
        let stopByte: UInt64
        if let end, end.isFinite, end > s {
            stopByte = min(dataEnd, wavDataOffset + UInt64(end * wavSampleRate) * UInt64(bytesPerFrame))
        } else {
            stopByte = dataEnd
        }
        guard stopByte > startByte else { return [] }
        let length = stopByte - startByte
        fh.seek(toFileOffset: startByte)
        let data = fh.readData(ofLength: Int(min(length, UInt64(Int32.max))))
        var result = [Int16](repeating: 0, count: data.count / 2)
        _ = result.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return result
    }

    deinit { try? wavFile?.close() }

    // MARK: 工具
    static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return s.components(separatedBy: bad).joined(separator: " ").trimmingCharacters(in: .whitespaces).isEmpty
            ? "未命名" : s.components(separatedBy: bad).joined(separator: " ")
    }

    static func wavWrap(pcm: [Int16], sampleRate: Double, channels: Int) -> Data {
        var d = Data()
        let dataLen = UInt32(pcm.count * 2)
        func le32(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        func le16(_ v: UInt16) -> [UInt8] { withUnsafeBytes(of: v.littleEndian) { Array($0) } }
        d.append(contentsOf: Array("RIFF".utf8)); d.append(contentsOf: le32(36 + dataLen))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); d.append(contentsOf: le32(16))
        d.append(contentsOf: le16(1)); d.append(contentsOf: le16(UInt16(channels)))
        d.append(contentsOf: le32(UInt32(sampleRate))); d.append(contentsOf: le32(UInt32(sampleRate) * UInt32(channels) * 2))
        d.append(contentsOf: le16(UInt16(channels * 2))); d.append(contentsOf: le16(16))
        d.append(contentsOf: Array("data".utf8)); d.append(contentsOf: le32(dataLen))
        pcm.withUnsafeBytes { d.append(contentsOf: $0) }
        return d
    }
}

// MARK: - 最小 ID3v2.3 写入器（TIT2/TPE1/TALB/APIC）
enum ID3Writer {
    static func tag(title: String, artist: String, album: String, coverData: Data?) -> Data {
        var frames = Data()
        frames.append(textFrame("TIT2", title))
        frames.append(textFrame("TPE1", artist))
        if !album.isEmpty { frames.append(textFrame("TALB", album)) }
        if let cover = coverData { frames.append(apicFrame(cover)) }

        var out = Data()
        out.append(contentsOf: Array("ID3".utf8))
        out.append(contentsOf: [3, 0, 0]) // v2.3, 无 flags
        let size = UInt32(frames.count)
        out.append(contentsOf: [UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F), UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)])
        out.append(frames)
        return out
    }

    private static func textFrame(_ id: String, _ text: String) -> Data {
        // encoding 1 = UTF-16 with BOM
        var body = Data([1])
        body.append(contentsOf: [0xFF, 0xFE])
        body.append(text.data(using: .utf16LittleEndian) ?? Data())
        return frame(id, body)
    }

    private static func apicFrame(_ cover: Data) -> Data {
        // 按字节头判断真实格式，别把 PNG 标成 JPEG
        let mime: String
        if cover.starts(with: [0xFF, 0xD8]) { mime = "image/jpeg" }
        else if cover.starts(with: [0x89, 0x50, 0x4E, 0x47]) { mime = "image/png" }
        else { return Data() }
        var body = Data([0]) // latin-1
        body.append(contentsOf: Array(mime.utf8))
        body.append(0)
        body.append(3) // front cover
        body.append(0) // 空描述
        body.append(cover)
        return frame("APIC", body)
    }

    private static func frame(_ id: String, _ body: Data) -> Data {
        var f = Data()
        f.append(contentsOf: Array(id.utf8.prefix(4)))
        let size = UInt32(body.count)
        f.append(contentsOf: [UInt8((size >> 24) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
        f.append(contentsOf: [0, 0]) // flags
        f.append(body)
        return f
    }
}
