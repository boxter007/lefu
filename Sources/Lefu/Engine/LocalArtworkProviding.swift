import Foundation

// MARK: - 本地封面能力（可选）
// 少数播放软件不上报封面到系统「正在播放」，但会把封面缓存在本地（如酷我 HDPicture）。
// 音源可声明一个本地封面提供者；引擎在系统未给封面时回退向它取。
// 与歌词后端一样，这是音源自带能力，引擎不含任何具体软件的分支。
protocol LocalArtworkProviding: AnyObject {
    /// 按曲目信息取本地封面字节（jpg/png）；取不到返回 nil。
    func artwork(title: String, artist: String, album: String) -> Data?
}
