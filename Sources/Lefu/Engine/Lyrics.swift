import Foundation
import LefuCore

// MARK: - 歌词抓取：本地后端 → 自家缓存 → LRCLIB → 网易云
enum LyricsFetcher {
    struct Line { let time: Double; let text: String }

    /// 顺序：自家缓存 → LRCLIB → 网易云；抓到即回写缓存。
    /// 本地歌词（汽水 KRC/LRC）不再写死在这里，由调用方经 localBackends 注入。
    static func fetchLRC(title: String, artist: String, duration: Double, offline: Bool, fallback: Bool, cacheDir: URL? = nil) async -> String? {
        let key = cacheKey(title: title, artist: artist)
        // 1. 自家缓存：离线模式的命脉
        if let dir = cacheDir, let cached = fromCache(dir, key) { return cached }
        // 2. LRCLIB
        if !offline, let lrc = await fromLrcLib(title: title, artist: artist, duration: duration) {
            saveToCache(lrc, dir: cacheDir, key: key)
            return lrc
        }
        // 3. 网易云兜底
        if fallback && !offline, let lrc = await fromNetease(title: title, artist: artist) {
            saveToCache(lrc, dir: cacheDir, key: key)
            return lrc
        }
        return nil
    }

    /// 结构化歌词入口：先遍历本地后端（汽水本地 KRC 可逐字、LRC 次之，零联网），
    /// 命中即返回；否则退回 fetchLRC 的整行 LRC 链路。
    static func fetchDocument(title: String, artist: String, duration: Double,
                              offline: Bool, fallback: Bool, cacheDir: URL?,
                              localBackends: [LyricsBackend] = []) async -> LyricsDocument? {
        for backend in localBackends {
            if let doc = await backend.document(title: title, artist: artist, duration: duration),
               !doc.lines.isEmpty {
                return doc
            }
        }
        guard let lrc = await fetchLRC(title: title, artist: artist, duration: duration,
                                       offline: offline, fallback: fallback, cacheDir: cacheDir) else { return nil }
        return LyricsDocument.parseLRC(lrc)
    }

    // MARK: 自建歌词缓存库（~/Music/乐府/.lyrics/）
    static func cacheKey(title: String, artist: String) -> String {
        Cutter.safeFileName("\(artist)-\(title)").lowercased()
    }

    private static func cachedURL(_ dir: URL, _ key: String) -> URL {
        dir.appendingPathComponent(key + ".lrc")
    }

    private static func fromCache(_ dir: URL, _ key: String) -> String? {
        let url = cachedURL(dir, key)
        guard let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    private static func saveToCache(_ lrc: String, dir: URL?, key: String) {
        guard let dir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? lrc.write(to: cachedURL(dir, key), atomically: true, encoding: .utf8)
    }

    // MARK: LRCLIB
    private static func fromLrcLib(title: String, artist: String, duration: Double) async -> String? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int(duration))),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("Lefu/1.0 (open-source Mac archiver)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let synced = json["syncedLyrics"] as? String, !synced.isEmpty { return synced }
        return nil
    }

    // MARK: 网易云
    private static func fromNetease(title: String, artist: String) async -> String? {        // 搜索
        // 显式 10 秒超时：默认 60s ×2 请求曾让歌词阶段长转圈（现在上游还有 8s 有界等待兜底）
        guard let searchURL = URL(string: "https://music.163.com/api/search/get/web?s=\(urlEncode(title))&type=1&limit=5"),
              let (sd, _) = try? await URLSession.shared.data(for: neteaseReq(searchURL)),
              let sj = try? JSONSerialization.jsonObject(with: sd) as? [String: Any],
              let songs = ((sj["result"] as? [String: Any])?["songs"] as? [[String: Any]])
        else { return nil }
        // 按歌手匹配挑最像的一首
        var songID: Int?
        for s in songs {
            let sTitle = s["name"] as? String ?? ""
            let artists = (s["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: "/") ?? ""
            if !title.isEmpty && (sTitle.contains(title) || title.contains(sTitle)) {
                if artist.isEmpty || artists.contains(artist) || artist.contains(artists) {
                    songID = s["id"] as? Int
                    break
                }
                if songID == nil { songID = s["id"] as? Int }
            }
        }
        guard let id = songID ?? songs.first?["id"] as? Int else { return nil }
        guard let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=1&kv=1"),
              let (ld, _) = try? await URLSession.shared.data(for: neteaseReq(lyricURL)),
              let lj = try? JSONSerialization.jsonObject(with: ld) as? [String: Any],
              let lrc = ((lj["lrc"] as? [String: Any])?["lyric"] as? String), !lrc.isEmpty
        else { return nil }
        return lrc
    }

    private static func neteaseReq(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        return req
    }

    private static func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

// MARK: - LRC 解析
enum LRCParser {
    static func parse(_ lrc: String) -> [(time: Double, text: String)] {
        var lines: [(Double, String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            // 一行可能有多个时间标签 [mm:ss.xx][mm:ss.xx]text
            let times = matches(of: raw)
            let content = raw.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty, !times.isEmpty else { continue }
            for t in times { lines.append((t, content)) }
        }
        return lines.sorted { $0.0 < $1.0 }
    }

    private static func matches(of line: String) -> [Double] {
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

    /// 当前应显示的行下标（-1 表示前奏）
    static func currentLine(_ lines: [(time: Double, text: String)], at t: Double) -> Int {
        var idx = -1
        for (i, l) in lines.enumerated() where l.time <= t { idx = i }
        return idx
    }
}
