import Foundation
import LefuCore

// MARK: - 喜马拉雅本地歌词后端（零联网）
// 喜马拉雅（Electron）把当前曲目的「歌词/AI 文稿」明文存放在 Chromium 的
// localStorage（LevelDB）：key = "lyric"，值是一个 JSON 对象：
//   { trackId, trackName, isAi, lyric: "[{start,end,text,wordPieces:[{start,end,word}]}]" }
// 注意：只有 App 内开启「自动字幕」时才会把当前曲目写进本地缓存。
// 本后端按 trackName 校验，缓存的是别的曲目（如上一集）就返回 nil，绝不返回错词。
final class XimalayaLocalLyricsBackend: LyricsBackend {
    private let dir: URL? = {
        let u = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.gemd.iting/Data/Library/Application Support/喜马拉雅/Local Storage/leveldb", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return u
    }()
    private var cache: [String: LyricsDocument] = [:]

    func document(title: String, artist: String, duration: Double) async -> LyricsDocument? {
        let key = Self.normalize(title)
        if let hit = cache[key] { return hit }
        var result: LyricsDocument?
        if let dir {
            for s in LevelDBReader.localStorageStrings(in: dir) {
                guard let data = s.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let trackName = obj["trackName"] as? String,
                      Self.match(trackName, key),
                      let lyricStr = obj["lyric"] as? String, !lyricStr.isEmpty else { continue }
                if let doc = Self.parseLyric(lyricStr), !doc.lines.isEmpty { result = doc; break }
            }
        }
        if let result { cache[key] = result }
        return result
    }

    func lrc(title: String, artist: String, duration: Double) async -> String? {
        guard let doc = await document(title: title, artist: artist, duration: duration) else { return nil }
        return doc.toLRC()
    }

    /// 全角转半角 + 小写 + 去空格
    static func normalize(_ s: String) -> String {
        let half = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        return half.lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// 曲名匹配：相等，或互为前缀（喜马拉雅标题常带「（点击评论区…）」等后缀）
    static func match(_ stored: String, _ wanted: String) -> Bool {
        let a = normalize(stored), b = wanted
        if a.isEmpty || b.isEmpty { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    /// lyric 字段是 JSON 数组字符串：[{start,end,text,wordPieces:[{start,end,word}]}]（毫秒）
    static func parseLyric(_ raw: String) -> LyricsDocument? {
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var lines: [LyricLine] = []
        for item in arr {
            guard let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty,
                  let startMs = (item["start"] as? NSNumber)?.doubleValue else { continue }
            var words: [LyricWord] = []
            if let wps = item["wordPieces"] as? [[String: Any]] {
                for w in wps {
                    guard let ws = (w["start"] as? NSNumber)?.doubleValue,
                          let we = (w["end"] as? NSNumber)?.doubleValue,
                          let wt = w["word"] as? String, !wt.isEmpty else { continue }
                    words.append(LyricWord(start: ws / 1000, duration: max(0, (we - ws) / 1000), text: wt))
                }
            }
            lines.append(LyricLine(start: startMs / 1000, text: text, words: words))
        }
        return lines.isEmpty ? nil : LyricsDocument(lines: lines.sorted { $0.start < $1.start })
    }
}
