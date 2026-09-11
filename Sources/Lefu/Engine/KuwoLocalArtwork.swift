import Foundation

// MARK: - 酷我本地封面
// 酷我不把封面上报到系统「正在播放」，但会缓存到 HDPicture。
// 引擎在系统未给封面时回退到这里（见 SessionController.onUpdate）。
final class KuwoLocalArtwork: LocalArtworkProviding {
    private var cache: [String: Data?] = [:]

    func artwork(title: String, artist: String, album: String) -> Data? {
        let key = KuwoLocalCache.normalize(artist) + "|" + KuwoLocalCache.normalize(title) + "|" + KuwoLocalCache.normalize(album)
        if let hit = cache[key] { return hit }
        var result: Data?
        if let base = KuwoLocalCache.base {
            let dir = base.appendingPathComponent("HDPicture", isDirectory: true)
            // 酷我封面文件名可能是「歌手 - 歌名」或「歌手 - 专辑」，两者都试
            for name in [title, album] where !name.isEmpty {
                if let url = KuwoLocalCache.findFile(in: dir, artist: artist, title: name, exts: [".jpg", ".png"]),
                   let data = try? Data(contentsOf: url), !data.isEmpty {
                    result = data
                    break
                }
            }
        }
        cache[key] = result
        return result
    }
}
