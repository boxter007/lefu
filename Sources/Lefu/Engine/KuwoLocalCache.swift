import Foundation

// MARK: - 酷我本地缓存定位与匹配（仅酷我音源使用）
// 目录：~/Library/Containers/com.wenyu.kwplayermac/Data/Caches/DocumentData
//   Lyric/<歌手> - <歌名> - <歌曲id>.lrcx
//   HDPicture/<歌手> - <歌名>.jpg
enum KuwoLocalCache {
    static let base: URL? = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.wenyu.kwplayermac/Data/Caches/DocumentData", isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }()

    /// 全角转半角 + 小写 + 去空格，用于容错匹配文件名
    static func normalize(_ s: String) -> String {
        let half = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        return half.lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// 在 dir 中找「归一化后以 歌手-歌名 开头」且扩展名匹配的文件
    static func findFile(in dir: URL, artist: String, title: String, exts: [String]) -> URL? {
        let a = normalize(artist), t = normalize(title)
        guard !a.isEmpty, !t.isEmpty,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        let key = a + "-" + t
        for name in names where exts.contains(where: { name.lowercased().hasSuffix($0) }) {
            let stem = name.contains(".") ? String(name[..<name.lastIndex(of: ".")!]) : name
            if normalize(stem).hasPrefix(key) { return dir.appendingPathComponent(name) }
        }
        return nil
    }
}
