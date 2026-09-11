import Foundation
import LefuCore

// MARK: - 汽水本地歌词后端
// 行为与改造前 LyricsFetcher 内的直接调用逐项一致：
// 先取本地原始 KRC（可逐字）→ parseKRC；否则退回本地整行 LRC → parseLRC；
// 任一环节解析出空行集就继续尝试下一级，最终取不到返回 nil。
final class SodaLocalLyricsBackend: LyricsBackend {
    func document(title: String, artist: String, duration: Double) async -> LyricsDocument? {
        if let krc = SodaLyrics.localKRC(title: title, artist: artist), !krc.isEmpty {
            let doc = LyricsDocument.parseKRC(krc)
            if !doc.lines.isEmpty { return doc }
        }
        if let lrc = SodaLyrics.localLyrics(title: title, artist: artist), !lrc.isEmpty {
            let doc = LyricsDocument.parseLRC(lrc)
            if !doc.lines.isEmpty { return doc }
        }
        return nil
    }

    /// 旁挂 .lrc 用：返回 localLyrics 的原始文本，逐字节等同改造前 fetchLRC 内联调用。
    func lrc(title: String, artist: String, duration: Double) async -> String? {
        if let local = SodaLyrics.localLyrics(title: title, artist: artist), !local.isEmpty {
            return local
        }
        return nil
    }
}
