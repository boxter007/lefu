import Foundation
import LefuCore

// MARK: - 酷狗本地歌词缓存定位（仅酷狗音源使用）
// 目录：~/Library/Containers/com.kugou.mac.Music/Data/Library/Application Support/
//        com.kugou.mac.Music/Caches/kgLyric
// 文件名：<歌手> - <歌名>_<md5>.krc（另有一份纯 <歌曲id>.krc）
// 注意：文件名里的歌名常被截短（如「苟活 (校园合唱版)(Live)」只存「苟活」），故按前缀匹配。
enum KuGouLyricsCache {
    static let dir: URL? = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.kugou.mac.Music/Data/Library/Application Support/com.kugou.mac.Music/Caches/kgLyric", isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }()

    /// 全角转半角 + 小写 + 去空格
    static func normalize(_ s: String) -> String {
        let half = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        return half.lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// 找与（歌手, 歌名）最匹配的 .krc：先精确、再按前缀（保留最长共同前缀）
    static func findFile(artist: String, title: String) -> URL? {
        guard let dir, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        let na = normalize(artist), nt = normalize(title)
        guard !na.isEmpty, !nt.isEmpty else { return nil }
        var best: (url: URL, score: Int)?
        for name in names where name.lowercased().hasSuffix(".krc") {
            var stem = String(name.dropLast(4))
            if let r = stem.range(of: #"_[0-9a-fA-F]{32}$"#, options: .regularExpression) {
                stem = String(stem[..<r.lowerBound])
            }
            guard let sep = stem.range(of: " - ") else { continue }   // 纯歌曲id命名，无法按名字匹配
            let fArtist = String(stem[..<sep.lowerBound])
            let fTitle = String(stem[sep.upperBound...])
            guard normalize(fArtist) == na else { continue }
            let nf = normalize(fTitle)
            if nf == nt { return dir.appendingPathComponent(name) }
            if nt.hasPrefix(nf) || nf.hasPrefix(nt) {
                let score = min(nf.count, nt.count)
                if best == nil || score > best!.score { best = (dir.appendingPathComponent(name), score) }
            }
        }
        return best?.url
    }
}

// MARK: - 酷狗本地歌词后端（零联网）
// .krc = "krc1" + zlib(正文 XOR 固定 16 字节掩码)；正文是逐字 KRC：
//   [起始ms,时长ms]<偏移ms,时长ms,0>字……
// 与汽水 KRC 同格式，直接复用 LyricsDocument.parseKRC。
final class KuGouLocalLyricsBackend: LyricsBackend {
    private var cache: [String: String?] = [:]

    func document(title: String, artist: String, duration: Double) async -> LyricsDocument? {
        guard let krc = localKRC(title: title, artist: artist) else { return nil }
        let doc = LyricsDocument.parseKRC(krc)
        return doc.lines.isEmpty ? nil : doc
    }

    func lrc(title: String, artist: String, duration: Double) async -> String? {
        guard let doc = await document(title: title, artist: artist, duration: duration) else { return nil }
        return doc.toLRC()
    }

    private func localKRC(title: String, artist: String) -> String? {
        let key = KuGouLyricsCache.normalize(artist) + "|" + KuGouLyricsCache.normalize(title)
        if let hit = cache[key] { return hit }
        var result: String?
        if let url = KuGouLyricsCache.findFile(artist: artist, title: title),
           let data = try? Data(contentsOf: url) {
            result = Self.decryptKRC(data)
        }
        cache[key] = result
        return result
    }

    /// .krc 解密：跳过 "krc1"，正文与固定掩码循环异或；NSData.zlib 需裸 deflate，故去掉 zlib 2 字节头。
    static func decryptKRC(_ data: Data) -> String? {
        let magic = Array("krc1".utf8)
        let mask: [UInt8] = [0x40,0x47,0x61,0x77,0x5e,0x32,0x74,0x47,0x51,0x36,0x31,0x2d,0xce,0xd2,0x6e,0x69]
        let bytes = [UInt8](data)
        guard bytes.count > magic.count + 2, Array(bytes.prefix(magic.count)) == magic else { return nil }
        var body = Array(bytes[magic.count...])
        for i in body.indices { body[i] ^= mask[i % mask.count] }
        let deflate = Data(body.dropFirst(2))
        guard let inflated = try? (deflate as NSData).decompressed(using: .zlib) as Data else { return nil }
        return String(data: inflated, encoding: .utf8)
    }
}
