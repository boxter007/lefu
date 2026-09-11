import Foundation
import LefuCore

// MARK: - 本地歌词后端
// 每个音源档案通过 MusicSource.lyricsBackends 声明自己的零联网本地歌词来源；
// LyricsFetcher 只依赖本协议，不再直接认识任何具体音源的缓存实现。
protocol LyricsBackend {
    /// 按曲目信息取一份结构化歌词文档；取不到返回 nil
    func document(title: String, artist: String, duration: Double) async -> LyricsDocument?
    /// 按曲目信息取原始整行 LRC 文本（旁挂 .lrc 用）；取不到返回 nil。
    /// 可选实现：默认无本地 LRC 能力。
    func lrc(title: String, artist: String, duration: Double) async -> String?
}

extension LyricsBackend {
    func lrc(title: String, artist: String, duration: Double) async -> String? { nil }
}
