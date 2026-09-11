import LefuCore

// MARK: - 酷狗音乐音源档案
// macOS 客户端（bundle com.kugou.mac.Music）。
// 经 MediaRemote 上报歌名/歌手/专辑/时长/播放位置/封面，字段齐全；
// 歌词取本地 kgLyric 缓存（.krc，可逐字），零联网。
final class KuGouSource: MusicSource {
    static let profile = SourceProfile(
        id: SourceID(raw: "kugou"),
        displayName: "酷狗音乐",
        bundleIDs: ["com.kugou.mac.Music"],
        symbolName: "music.note",
        detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                    playSignal: .ratePreferred,
                                    exposesElapsed: true, exposesDuration: true),
        control: .nowPlayingCLI,
        enabledByDefault: false)

    /// 酷狗本地歌词：Caches/kgLyric 的加密 .krc（零联网、逐字）
    static let lyricsBackends: [LyricsBackend] = [KuGouLocalLyricsBackend()]
}
