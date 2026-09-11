import LefuCore

// MARK: - QQ音乐音源档案
// macOS 客户端（bundle com.tencent.QQMusicMac）。
// 经 MediaRemote 上报歌名/歌手/专辑/时长/封面，字段齐全；
// 歌词走通用在线链（本地缓存是加密 QRC，暂未接入本地歌词）。
final class QQMusicSource: MusicSource {
    static let profile = SourceProfile(
        id: SourceID(raw: "qqmusic"),
        displayName: "QQ音乐",
        bundleIDs: ["com.tencent.QQMusicMac"],
        symbolName: "music.note.tv",
        detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                    playSignal: .ratePreferred,
                                    exposesElapsed: true, exposesDuration: true),
        control: .nowPlayingCLI,
        enabledByDefault: false)
}
