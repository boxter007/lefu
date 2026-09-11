import LefuCore

// MARK: - 喜马拉雅音源档案
// macOS 客户端（Electron，bundle com.gemd.iting）。
// 经 MediaRemote 上报标题/（合集名作 artist）/时长/播放位置/封面；
// 歌词取本地 localStorage 缓存（需在 App 内开启「自动字幕」），零联网。
final class XimalayaSource: MusicSource {
    static let profile = SourceProfile(
        id: SourceID(raw: "ximalaya"),
        displayName: "喜马拉雅",
        bundleIDs: ["com.gemd.iting"],
        symbolName: "headphones",
        detection: DetectionProfile(confirmTicks: 2, pollInterval: 1.0,
                                    playSignal: .ratePreferred,
                                    exposesElapsed: true, exposesDuration: true),
        control: .nowPlayingCLI,
        enabledByDefault: false)

    /// 喜马拉雅本地歌词：Chromium localStorage 的 lyric 缓存（零联网、逐字）
    static let lyricsBackends: [LyricsBackend] = [XimalayaLocalLyricsBackend()]
}
