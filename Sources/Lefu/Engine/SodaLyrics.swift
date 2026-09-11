import Foundation

// MARK: - 汽水本地歌词提取（零联网）
// 移植自 engine/soda_lyrics_local.py，逻辑逐函数对齐：
// 数据源: ~/Library/Application Support/SodaMusic/LunaCacheV2/entries.db
// 格式: MessagePack 追加日志; 歌词记录 = KRC逐字LRC文本 + "krck"键 + track_id
// KRC 行格式: [起始ms,时长ms]<词内偏移,词长>词1 <偏移,长>词2 ...
enum SodaLyrics {
    static var dbURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SodaMusic/LunaCacheV2/entries.db")
    }

    struct Entry {
        var krcLrc = ""
        var lineLrc = ""
        var rawKRC = ""   // 原始 KRC 正文（含 <offset,dur,0> 逐字标签），供结构化解析
    }

    // 扫描结果内存缓存（db 是追加日志，按文件大小判断是否需要重扫）
    private static var cache: (size: Int, index: [String: Entry])?
    private static var wideCache: (size: Int, index: [String: String])?

    /// 按 歌名(+歌手) 从本地缓存找歌词，返回标准 LRC 文本
    /// 两级索引：先精确 krck 索引，未命中再走宽索引（rc/content 类型记录）
    static func localLyrics(title: String, artist: String) -> String? {
        guard !title.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: dbURL) else { return nil }
        let bytes = [UInt8](data)
        let size = data.count

        let index = scanIndex(bytes: bytes, size: size)
        let artistB = Array(artist.utf8)

        var wide: [String: String]? = nil // 惰性：只在精确索引未命中时才扫宽索引
        for tid in titleCandidates(bytes, title: title) {
            if let entry = index[tid] {
                let lyric = cjkCount(entry.lineLrc) >= cjkCount(entry.krcLrc) ? entry.lineLrc : entry.krcLrc
                if lyric.count > 30 && artistOK(bytes, tid: tid, artistB: artistB) {
                    return lyric
                }
            }
            if wide == nil { wide = scanWide(bytes: bytes, size: size) }
            if let lyric = wide?[tid], lyric.count > 30 && artistOK(bytes, tid: tid, artistB: artistB) {
                return lyric
            }
        }
        return nil
    }

    /// 汽水本地原始 KRC 文本（逐字高亮用）；与 localLyrics 同一精确索引，不输出宽索引兜底
    static func localKRC(title: String, artist: String) -> String? {
        guard !title.isEmpty, let data = try? Data(contentsOf: dbURL) else { return nil }
        let bytes = [UInt8](data)
        let index = scanIndex(bytes: bytes, size: data.count)
        let artistB = Array(artist.utf8)
        for tid in titleCandidates(bytes, title: title) {
            if let entry = index[tid], entry.rawKRC.count > 30, artistOK(bytes, tid: tid, artistB: artistB) {
                return entry.rawKRC
            }
        }
        return nil
    }

    // MARK: 精确索引：记录特征 = 歌词字符串 + \xc2(false) + \xa3krck + ... + \xb3<track_id>
    private static func scanIndex(bytes: [UInt8], size: Int) -> [String: Entry] {
        if let c = cache, c.size == size { return c.index }
        var out: [String: Entry] = [:]
        let marker: [UInt8] = [0xC2, 0xA3] + Array("krck".utf8)
        var pos = 0
        while let r = find(bytes, marker, from: pos) {
            let mEnd = r.upperBound
            pos = mEnd
            guard let raw = parseStringBefore(bytes, end: r.lowerBound) else { continue }
            let after = Array(bytes[mEnd..<min(mEnd + 250, bytes.count)])
            guard let tid = firstTrackID(after) else { continue }
            var e = out[tid] ?? Entry()
            let rawText = String(decoding: raw, as: UTF8.self)
            let krc = krcToLrc(raw)
            let line = plainLrc(raw)
            if krc.count > e.krcLrc.count { e.krcLrc = krc }
            if line.count > e.lineLrc.count { e.lineLrc = line }
            if rawText.count > e.rawKRC.count { e.rawKRC = rawText }
            out[tid] = e
        }
        cache = (size, out)
        return out
    }

    // MARK: 宽索引：扫所有 KRC 正文段（相邻 <1000B 聚类为同一首歌），不依赖 krck 键
    private static func scanWide(bytes: [UInt8], size: Int) -> [String: String] {
        if let c = wideCache, c.size == size { return c.index }
        var out: [String: String] = [:]
        let headRe = try! NSRegularExpression(pattern: #"\[(\d{3,7}),\d{3,7}\]<\d{1,6},\d{1,6},\d{1,2}>"#)
        let text = String(decoding: bytes, as: UTF8.self)
        let ns = text as NSString
        // 正文按位置聚类成段
        var segs: [(start: Int, end: Int)] = []
        headRe.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let h = m.range.location
            if let last = segs.last, h - last.end < 1000 {
                segs[segs.count - 1].end = h
            } else {
                segs.append((h, h))
            }
        }
        for seg in segs {
            let raw: [UInt8]
            if let parsed = parseStringBefore(bytes, end: min(seg.end + 200, size)) {
                raw = parsed
            } else {
                raw = Array(bytes[max(0, seg.start)..<min(size, seg.end + 600)])
            }
            let lo = max(0, seg.start - 4000)
            let hi = min(size, seg.end + 4000)
            let slice = Array(bytes[lo..<hi])
            guard let tid = firstTrackID(slice) else { continue }
            let lrc = krcToLrc(raw)
            if lrc.count > (out[tid] ?? "").count { out[tid] = lrc }
        }
        wideCache = (size, out)
        return out
    }

    // MARK: msgpack 字符串提取：向前扫 str 头（d9/da/db），长度字段恰好落在结束位置
    private static func parseStringBefore(_ bytes: [UInt8], end e: Int, maxBack: Int = 65536) -> [UInt8]? {
        let lo = max(0, e - maxBack)
        var s = e - 5
        while s > lo {
            let b0 = bytes[s]
            if b0 == 0xD9 {
                let l = Int(bytes[s + 1])
                if l >= 100 && s + 2 + l == e { return Array(bytes[(s + 2)..<e]) }
            } else if b0 == 0xDA {
                guard s + 3 <= e else { s -= 1; continue }
                let l = Int(bytes[s + 1]) << 8 | Int(bytes[s + 2])
                if l >= 100 && s + 3 + l == e { return Array(bytes[(s + 3)..<e]) }
            } else if b0 == 0xDB {
                guard s + 5 <= e else { s -= 1; continue }
                let l = Int(bytes[s + 1]) << 24 | Int(bytes[s + 2]) << 16 | Int(bytes[s + 3]) << 8 | Int(bytes[s + 4])
                if l >= 100 && s + 5 + l == e { return Array(bytes[(s + 5)..<e]) }
            }
            s -= 1
        }
        return nil
    }

    // MARK: track_id = 0xB3(fixstr19) + 19 位 ASCII 数字
    private static func firstTrackID(_ bytes: [UInt8]) -> String? {
        var i = 0
        while i + 19 < bytes.count + 1 {
            if i + 19 >= bytes.count { break }
            if bytes[i] == 0xB3 {
                var ok = true
                for j in 1...19 where !(0x30...0x39).contains(bytes[i + j]) { ok = false; break }
                if ok { return String(decoding: bytes[(i + 1)..<(i + 20)], as: UTF8.self) }
            }
            i += 1
        }
        return nil
    }

    // MARK: 歌名候选：歌名出现位置 ±2500B 内的 track_id 按出现次数排序
    private static func titleCandidates(_ bytes: [UInt8], title: String, back: Int = 2500, fwd: Int = 2500) -> [String] {
        let tb = Array(title.utf8)
        guard !tb.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        var order: [String] = []
        var i = 0
        while let r = find(bytes, tb, from: i) {
            let lo = max(0, r.lowerBound - back)
            let hi = min(bytes.count, r.upperBound + fwd)
            scanTrackIDs(bytes, in: lo..<hi) { tid in
                if counts[tid] == nil { order.append(tid) }
                counts[tid, default: 0] += 1
            }
            i = r.lowerBound + 1
        }
        return order.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    private static func scanTrackIDs(_ bytes: [UInt8], in range: Range<Int>, handler: (String) -> Void) {
        var j = range.lowerBound
        let hi = min(range.upperBound, bytes.count - 19)
        while j < hi {
            if bytes[j] == 0xB3 {
                var ok = true
                for k in 1...19 where !(0x30...0x39).contains(bytes[j + k]) { ok = false; break }
                if ok {
                    handler(String(decoding: bytes[(j + 1)..<(j + 20)], as: UTF8.self))
                    j += 19
                }
            }
            j += 1
        }
    }

    // MARK: 歌手校验：tid 出现处附近应能找到歌手名；多歌手拆开任一命中即过
    private static func artistOK(_ bytes: [UInt8], tid: String, artistB: [UInt8]) -> Bool {
        guard !artistB.isEmpty else { return true }
        let artist = String(decoding: artistB, as: UTF8.self)
        let parts = artist.split(whereSeparator: { ",，/、&".contains($0) })
            .map { Array(String($0).trimmingCharacters(in: .whitespaces).utf8) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return true }
        let tidB = Array(tid.utf8)
        var i = 0
        while let r = find(bytes, tidB, from: i) {
            let ctx = Array(bytes[r.lowerBound..<min(bytes.count, r.lowerBound + 4000)])
            if parts.allSatisfy({ find(ctx, $0, from: 0) != nil }) { return true }
            if parts.count == 1, find(ctx, parts[0], from: 0) != nil { return true }
            i = r.lowerBound + 1
        }
        return false
    }

    // MARK: KRC 逐字文本 → 标准逐行 LRC
    private static func krcToLrc(_ raw: [UInt8]) -> String {
        let text = String(decoding: raw, as: UTF8.self)
        let lineRe = try! NSRegularExpression(pattern: #"\[(\d{3,7}),\d{3,7}\]((?:<\d{1,6},\d{1,6},\d{1,2}>[^\n\[]*)+)"#)
        let wordRe = try! NSRegularExpression(pattern: #"<\d{1,6},\d{1,6},\d{1,2}>([^\n<]*)"#)
        let ns = text as NSString
        var out: [String] = []
        lineRe.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.range(at: 1).location != NSNotFound, m.range(at: 2).location != NSNotFound else { return }
            let startMs = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let body = ns.substring(with: m.range(at: 2))
            let bns = body as NSString
            var words: [String] = []
            wordRe.enumerateMatches(in: body, range: NSRange(location: 0, length: bns.length)) { wm, _, _ in
                guard let wm, wm.range(at: 1).location != NSNotFound else { return }
                words.append(bns.substring(with: wm.range(at: 1)))
            }
            let line = words.joined().trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { out.append(msToLrcTag(startMs) + line) }
        }
        return out.joined(separator: "\n")
    }

    // MARK: 普通 LRC 行提取（有些记录直接存 [mm:ss.xx]text）
    private static func plainLrc(_ raw: [UInt8]) -> String {
        let text = String(decoding: raw, as: UTF8.self)
        let re = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})\.(\d{2,3})\]([^\n\[\r]+)"#)
        let ns = text as NSString
        var out: [String] = []
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.range(at: 4).location != NSNotFound else { return }
            let mm = ns.substring(with: m.range(at: 1))
            let ss = ns.substring(with: m.range(at: 2))
            let frac = String(ns.substring(with: m.range(at: 3)).prefix(2))
            let line = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { out.append("[\(String(format: "%02d", Int(mm) ?? 0)):\(ss).\(frac)]\(line)") }
        }
        return out.joined(separator: "\n")
    }

    private static func msToLrcTag(_ ms: Int) -> String {
        let s = ms / 1000, ms2 = ms % 1000
        return String(format: "[%02d:%02d.%02d]", (s / 60) % 100, s % 60, ms2 / 10)
    }

    private static func cjkCount(_ s: String) -> Int {
        s.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
    }

    // MARK: 字节查找（朴素匹配，6MB 库毫无压力）
    private static func find(_ haystack: [UInt8], _ needle: [UInt8], from: Int) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        var i = max(0, from)
        let last = haystack.count - needle.count
        while i <= last {
            if haystack[i] == needle[0] {
                var ok = true
                for j in 1..<needle.count where haystack[i + j] != needle[j] { ok = false; break }
                if ok { return i..<(i + needle.count) }
            }
            i += 1
        }
        return nil
    }
}
