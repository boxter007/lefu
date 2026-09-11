import LefuCore

// MARK: - 汽水音乐音源档案
// 参数与改造前的写死行为逐项一致：系统「正在播放」主通道（nowplaying-cli → MediaRemote），
// 连续稳定 2 拍确认，优先播放速率判定，不暴露 elapsed。
final class SodaSource: MusicSource {
    static let profile = SourceProfile(
        id: SourceID(raw: "soda"),
        displayName: "汽水音乐",
        bundleIDs: ["com.soda.music"],
        symbolName: "music.note",
        detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                    playSignal: .ratePreferred, exposesElapsed: false),
        control: .nowPlayingCLI,
        enabledByDefault: true)

    /// 汽水本地歌词：entries.db 的 KRC/LRC（零联网）
    static let lyricsBackends: [LyricsBackend] = [SodaLocalLyricsBackend()]
}
