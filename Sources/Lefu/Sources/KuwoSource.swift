import LefuCore

// MARK: - 酷我音乐音源档案
// macOS 客户端（bundle com.wenyu.kwplayermac）。
// 经 MediaRemote 上报歌名/歌手/专辑/时长/播放位置与 PlaybackRate，字段较全；
// 封面目前不上报（缺 ArtworkData），歌词走通用在线链（自建缓存 → LRCLIB → 网易云）。
final class KuwoSource: MusicSource {
    static let profile = SourceProfile(
        id: SourceID(raw: "kuwo"),
        displayName: "酷我音乐",
        bundleIDs: ["com.wenyu.kwplayermac"],
        symbolName: "music.quarternote.3",
        detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                    playSignal: .ratePreferred,
                                    exposesElapsed: true, exposesDuration: true),
        control: .nowPlayingCLI,
        enabledByDefault: false)

    /// 酷我本地歌词：DocumentData/Lyric 的加密 .lrcx（零联网；去逐字标记后整行）
    static let lyricsBackends: [LyricsBackend] = [KuwoLocalLyricsBackend()]
    /// 酷我本地封面：DocumentData/HDPicture（酷我不上报封面到系统）
    static let artworkProvider: LocalArtworkProviding? = KuwoLocalArtwork()
}
