import LefuCore

// MARK: - Apple Music 音源档案
// 系统自带「音乐」App（bundle com.apple.Music）。
// 它是 macOS 一等公民：经 MediaRemote 上报歌名/歌手/专辑/时长/封面，且上报 PlaybackRate 与
// ElapsedTime（汽水不报）。故优先用播放速率判定「真的在播」，并声明暴露位置与时长。
// 歌词：无干净可用的本地歌词库（缓存只有 URL/封面缓存），走通用在线链（自建缓存 → LRCLIB → 网易）。
final class AppleMusicSource: MusicSource {
    static let profile = SourceProfile(
        id: SourceID(raw: "applemusic"),
        displayName: "Apple Music",
        bundleIDs: ["com.apple.Music"],
        symbolName: "music.note.list",
        detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                    playSignal: .ratePreferred,
                                    exposesElapsed: true, exposesDuration: true),
        control: .nowPlayingCLI,
        enabledByDefault: false)
}
