import LefuCore

// MARK: - 网易云音乐音源档案
// macOS 客户端（bundle com.netease.163music）。
// 经 MediaRemote 上报歌名/歌手/专辑/时长/封面与 PlaybackRate，但 elapsed 恒为 0（同汽水），
// 故优先按播放速率判定「真的在播」，不声明暴露播放位置。
// 歌词：客户端只把歌词联网取回显示、不落地可读副本（无 .lrc、无歌词表、缓存只有封面/音频），
// 因此不做本地后端，走通用在线链（自建缓存 → LRCLIB → 网易云接口）。
final class NetEaseSource: MusicSource {
    static let profile = SourceProfile(
        id: SourceID(raw: "netease"),
        displayName: "网易云音乐",
        bundleIDs: ["com.netease.163music"],
        symbolName: "cloud.fill",
        detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                    playSignal: .ratePreferred,
                                    exposesElapsed: false, exposesDuration: true),
        control: .nowPlayingCLI,
        enabledByDefault: false)
}
