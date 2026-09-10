import AVFoundation

// MARK: - 静音切分器（裁曲页无 jsonl 时间轴时的兜底）
// 思路移植自早期 Python 静音切分：按窗口 RMS 找长静音间隙，取间隙中点做切点，
// 两切点之间为一段，短于最短收录时长的段丢弃。
// 与 Cutter 的静音规则同源：录音中没放歌时 BlackHole 收到的是数字零，RMS 接近 0。
enum SilenceSplitter {
    /// 按静音间隙把整场录音切成分段。找不到任何长静音时返回"整段一段"（自然回落为整段处理）
    static func split(wavURL: URL, minSegment: Double) -> [TimelineEntry] {
        guard let windows = windowRMS(wavURL: wavURL) else { return [] }
        guard !windows.isEmpty else { return [] }

        let threshold = 0.002          // ≈ -54dB RMS：只有真正的数字静音才会低于它
        let winSeconds = 0.25
        let minGapWindows = Int(2.0 / winSeconds)   // 静音持续 ≥2s 才算切点，防误切歌内弱音

        // 扫描长静音段，取中点索引做切点
        var cuts: [Int] = []
        var runStart: Int? = nil
        for (idx, rms) in windows.enumerated() {
            if rms < threshold {
                if runStart == nil { runStart = idx }
            } else {
                if let rs = runStart, idx - rs >= minGapWindows {
                    cuts.append((rs + idx) / 2)
                }
                runStart = nil
            }
        }
        if let rs = runStart, windows.count - rs >= minGapWindows {
            cuts.append((rs + windows.count) / 2)
        }

        // 切点 → 秒边界
        var boundaries: [Double] = [0]
        boundaries += cuts.map { Double($0) * winSeconds }
        boundaries.append(Double(windows.count) * winSeconds)

        var entries: [TimelineEntry] = []
        for k in 0..<(boundaries.count - 1) {
            let s = boundaries[k]
            let e = boundaries[k + 1]
            guard e - s >= minSegment else { continue }   // 短段丢弃（与时间轴模式同规则）
            entries.append(TimelineEntry(t: s,
                                         title: String(format: "轨道%02d", entries.count + 1),
                                         artist: "", album: "", duration: e - s))
        }
        return entries
    }

    // MARK: 分窗 RMS（分块读取，内存占用与文件长度无关）
    private static func windowRMS(wavURL: URL) -> [Double]? {
        guard let file = try? AVAudioFile(forReading: wavURL) else { return nil }
        let format = file.processingFormat
        let sr = format.sampleRate
        let ch = Int(format.channelCount)
        let win = Int(sr * 0.25)
        guard sr > 0, ch > 0, win > 0 else { return nil }

        let chunkCap = AVAudioFrameCount(sr * 10)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCap) else { return nil }

        var windows: [Double] = []
        var carry: [Float] = []

        func drain() {
            var pos = 0
            while pos + win <= carry.count {
                var e = 0.0
                for j in pos..<(pos + win) {
                    let v = Double(carry[j])
                    e += v * v
                }
                windows.append((e / Double(win)).squareRoot())
                pos += win
            }
            if pos > 0 { carry.removeFirst(pos) }
        }

        while file.framePosition < file.length {
            do { try file.read(into: buf) } catch { break }
            let n = Int(buf.frameLength)
            guard n > 0 else { break }
            if let chData = buf.floatChannelData {
                var mono = [Float](repeating: 0, count: n)
                for c in 0..<ch {
                    let p = chData[c]
                    for i in 0..<n { mono[i] += p[i] }
                }
                let scale = 1.0 / Float(ch)
                for i in 0..<n { mono[i] *= scale }
                carry.append(contentsOf: mono)
            }
            drain()
        }
        // 收尾不足一个窗口的尾巴也评一个窗，保证总时长准确
        if !carry.isEmpty {
            var e = 0.0
            for v in carry {
                let x = Double(v)
                e += x * x
            }
            windows.append((e / Double(carry.count)).squareRoot())
        }
        return windows
    }
}
