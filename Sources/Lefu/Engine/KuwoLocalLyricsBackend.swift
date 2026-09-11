import Foundation
import LefuCore

// MARK: - 酷我本地歌词后端（零联网）
// 酷我把歌词缓存在本地 .lrcx：utf8\r\n + base64(密文) + \r\noffset=N。
// 密文 = 明文按 7 字节循环密钥 "yeelion" 异或；明文为标准逐字 LRC。
// 去掉 <...> 逐字标记后用 parseLRC 取整行歌词；旁挂 .lrc 由 toLRC 产出。
final class KuwoLocalLyricsBackend: LyricsBackend {
    private var cache: [String: String?] = [:]

    func document(title: String, artist: String, duration: Double) async -> LyricsDocument? {
        guard let raw = localLRC(title: title, artist: artist) else { return nil }
        let cleaned = raw.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        let doc = LyricsDocument.parseLRC(cleaned)
        return doc.lines.isEmpty ? nil : doc
    }

    func lrc(title: String, artist: String, duration: Double) async -> String? {
        guard let doc = await document(title: title, artist: artist, duration: duration) else { return nil }
        return doc.toLRC()
    }

    private func localLRC(title: String, artist: String) -> String? {
        let key = KuwoLocalCache.normalize(artist) + "|" + KuwoLocalCache.normalize(title)
        if let hit = cache[key] { return hit }
        var result: String?
        if let base = KuwoLocalCache.base {
            let dir = base.appendingPathComponent("Lyric", isDirectory: true)
            if let url = KuwoLocalCache.findFile(in: dir, artist: artist, title: title, exts: [".lrcx"]),
               let data = try? Data(contentsOf: url) {
                result = Self.decryptLRCX(data)
            }
        }
        cache[key] = result
        return result
    }

    /// .lrcx 解密：定位 utf8\r\n 与 \r\noffset 之间的 base64，解码后按 "yeelion" 循环异或。
    static func decryptLRCX(_ data: Data) -> String? {
        let header = Array("utf8\r\n".utf8)
        let terminator = Array("\r\noffset".utf8)
        let bytes = [UInt8](data)
        guard bytes.count > header.count, Array(bytes.prefix(header.count)) == header else { return nil }
        guard let end = index(of: terminator, in: bytes, from: header.count) else { return nil }
        var b64 = String(decoding: bytes[header.count..<end], as: UTF8.self)
        b64 = b64.trimmingCharacters(in: .whitespacesAndNewlines)
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let cipher = Data(base64Encoded: b64) else { return nil }
        let key = Array("yeelion".utf8)
        var out = [UInt8](cipher)
        for i in out.indices { out[i] ^= key[i % key.count] }
        return String(data: Data(out), encoding: .utf8)
    }

    private static func index(of needle: [UInt8], in hay: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, hay.count >= needle.count else { return nil }
        var i = max(0, from)
        while i + needle.count <= hay.count {
            if Array(hay[i..<i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }
}
