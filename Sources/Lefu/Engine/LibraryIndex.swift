import Foundation

// MARK: - 府库索引
// 「库中已有」的统一判定。旧判定有两套且互相打架：
//   · 行徽章：只看【当天日期目录】、按歌名子串（"十年" 会误命中 "十年 - Live"）
//   · 落盘跳过：只看今天、按 artist-title 精确路径
// 这里统一为：递归整个输出目录（含历次日期目录、裁曲、用户导入的专辑），
// 按与落盘同源的 safeFileName("artist - title") 精确匹配（忽略扩展名、.lrc 与隐藏项）。
// SessionController 与 Cutter 都改用它，保证「行标跳过」= 「实际不落盘」。
enum LibraryIndex {
    private static let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "aac"]

    /// 与落盘同源的清名规则（原 Cutter.safeFileName）。
    static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = s.components(separatedBy: bad).joined(separator: " ")
        return cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "未命名" : cleaned
    }

    /// 整个输出目录里是否已有该曲。
    static func contains(title: String, artist: String, in root: URL) -> Bool {
        let key = safeFileName(artist + " - " + title).lowercased()
        guard key != "未命名", !key.isEmpty else { return false }
        return scan(root, depth: 0, key: key)
    }

    private static func scan(_ dir: URL, depth: Int, key: String) -> Bool {
        guard depth <= 4 else { return false }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return false }
        for name in entries where !name.hasPrefix(".") {     // 隐藏项（如 .lyrics）不算
            let u = dir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if scan(u, depth: depth + 1, key: key) { return true }
                continue
            }
            guard audioExts.contains((name as NSString).pathExtension.lowercased()) else { continue }
            if (name as NSString).deletingPathExtension.lowercased() == key { return true }
        }
        return false
    }
}
