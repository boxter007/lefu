# 接入新的音乐软件（音源）指南

> 面向贡献者。目标：把「适配一个新的音乐软件」变成一次性、低风险、可被独立审查的工作。
> 相关：设计规格（superpowers/specs/2026-09-11-multi-source-provider-design.md）

## 1. 这份文档给谁

给想在乐府里支持一个新的音乐软件的人。读完你应当能：新建一个音源、把它接进引擎、并知道怎么自测与验收。

## 2. 心智模型

- 一个音源 = 一份「档案」（纯数据）+ 可选的本地歌词后端 + 可选的本地封面提供者 + 在登记处登记一行。
- 元数据与「正在播放」默认全部来自系统（MediaRemote / nowplaying-cli）；歌名/歌手/专辑/时长/封面都以系统上报为准，乐府不解析任何软件的私有数据库来取元数据。
- 例外：若软件本地缓存了封面却不上报到系统，音源可声明一个「本地封面提供者」作为兜底（见 §3.4）。它只补封面，取不到就是无封面，不影响其它元数据。
- 引擎里不含任何具体软件的分支。汽水相关的代码只存在于它自己的档案与本地歌词后端里。

职责边界：

    监听层（NowPlayingMonitor）   只产「每拍正在播放事实 + 客户端 bundle id」，不做歌名判断
    SessionController            确认/去抖/切歌/收卷/挂机；按当前音源档案取参数
    LyricsFetcher                只依赖 LyricsBackend 协议；顺序：本地后端 → 自建缓存 → LRCLIB → 网易
    SourceRegistry               内置音源清单与解析（bundle → 档案）
    SourceProfile（LefuCore）    纯数据档案，可单测
    LyricsBackend                本地歌词能力；每个音源自带，可为空
    LocalArtworkProviding        本地封面兜底；每个音源自带，可为空

## 3. 接入三件事

### 3.1 拿到 bundle id

在该软件正在播放时执行：

    /opt/homebrew/bin/nowplaying-cli get-raw | grep -i BundleIdentifier

或直接读系统键 kMRMediaRemoteNowPlayingInfoClientBundleIdentifier。
若该软件有多个进程/变体，可给 bundleIDs 填多个（它是 Set）。

### 3.2 写档案：Sources/Lefu/Sources/YourNameSource.swift

    import LefuCore

    // MARK: - 示例音乐音源档案
    final class YourNameSource: MusicSource {
        static let profile = SourceProfile(
            id: SourceID(raw: "yourname"),          // 稳定、唯一、小写，用于持久化启用状态
            displayName: "示例音乐",                  // 设置页与来源徽标显示
            bundleIDs: ["com.example.music"],        // §3.1 得到的标识
            symbolName: "music.note",                // SF Symbol，设置页图标
            detection: DetectionProfile(
                confirmTicks: 2,
                pollInterval: 1.0,
                playSignal: .ratePreferred,
                exposesElapsed: true,
                exposesDuration: true),
            control: .mediaRemote,
            enabledByDefault: false)                 // 新音源一律 false
    }

新音源不加 lyricsBackends 时不写本地歌词，自动走通用在线链；不加 artworkProvider 时不补本地封面。二者都是合法的。

### 3.3 可选：本地歌词后端：Sources/Lefu/Engine/YourNameLocalLyricsBackend.swift

只有当该软件有离线本地歌词（自带数据库/缓存）时才需要写。实现 LyricsBackend：

    import Foundation
    import LefuCore

    final class YourNameLocalLyricsBackend: LyricsBackend {
        // 结构化歌词（可逐字更好）；取不到返回 nil
        func document(title: String, artist: String, duration: Double) async -> LyricsDocument? {
            // 示例：读你的数据库，拿到 LRC/KRC 文本后解析
            // let raw = ...
            // let doc = LyricsDocument.parseLRC(raw)
            // return doc.lines.isEmpty ? nil : doc
            return nil
        }

        // 原始整行 LRC（旁挂 .lrc 用）。只有实现了它，才会写本地歌词旁挂。
        // 默认实现返回 nil，可省略。
        func lrc(title: String, artist: String, duration: Double) async -> String? {
            return nil
        }
    }

然后在档案里声明：

    static let lyricsBackends: [LyricsBackend] = [YourNameLocalLyricsBackend()]

约定：document 负责屏幕逐字/整行显示；lrc 负责旁挂 .lrc。只实现 document 也能显示歌词，但不会写出本地 .lrc 旁挂（会退回在线链）。

若该软件是 Electron/Chromium（歌词藏在本机 localStorage 的 LevelDB 里，如喜马拉雅），可复用 `Sources/Lefu/Engine/LevelDBReader.swift`：它只读解析 Snappy 压缩块、SSTable（`.ldb`）与 WAL（`.log`），取出明文 JSON 后再自行解析。注意这类缓存往往只保留「当前/最近曲目」，务必按曲名或曲目 id 校验后再返回，避免给错词。

### 3.4 可选：本地封面提供者：Sources/Lefu/Engine/YourNameLocalArtwork.swift

仅当该软件**本地缓存了封面、却不上报到系统**时才需要写。实现 LocalArtworkProviding：

    import Foundation

    final class YourNameLocalArtwork: LocalArtworkProviding {
        // 按歌名/歌手/专辑在本地找封面图片字节（jpg/png）；取不到返回 nil
        func artwork(title: String, artist: String, album: String) -> Data? {
            return nil
        }
    }

然后在档案里声明：

    static let artworkProvider: LocalArtworkProviding? = YourNameLocalArtwork()

引擎在系统未给封面时调用它兜底（见 SessionController.onUpdate）；系统已带封面则不调用。它只补封面，不影响其它元数据。

### 3.5 登记一行

编辑 Sources/Lefu/Sources/MusicSource.swift，把新档案加进清单：

    static let shared = SourceRegistry(sources: [SodaSource.self, YourNameSource.self])

这是唯一需要登记新音源的地方。设置页、监听门禁、歌词后端、封面兜底都从这里取。

### 3.6 构建与打包

    swift build --disable-sandbox
    ./scripts/build_app.sh        # 若 CLT 下 SPM 沙箱报错，见 README 的本地打包说明

## 4. 字段参考

| 字段 | 含义 | 默认 | 建议 |
|---|---|---|---|
| id.raw | 稳定唯一标识，用于持久化启用状态 | 必填 | 小写、不随显示名变化 |
| displayName | 设置页/徽标显示名 | 必填 | 用软件正式名 |
| bundleIDs | 系统上报的客户端标识集合 | 必填 | 用 §3.1 实测值 |
| symbolName | SF Symbol 名称 | 必填 | 与软件气质相符 |
| detection.confirmTicks | 标题连续稳定几拍才确认切歌 | 2 | 抖动大的软件可调高到 3 |
| detection.pollInterval | 轮询间隔（秒） | 1.0 | 一般保持 1.0 |
| detection.playSignal | 判定「真的在播」的方式 | .ratePreferred | 见下 |
| detection.exposesElapsed | 该源是否上报播放位置 | false | 目前仅入档，UI 未接线 |
| detection.exposesDuration | 该源是否上报总时长 | true | 目前仅入档 |
| control | 切歌控制通道 | .mediaRemote | 见下 |
| enabledByDefault | 默认是否启用 | false | 新音源一律 false |

playSignal 取值：

- .ratePreferred：优先看系统上报的 PlaybackRate（rate 大于 0 即在播），字段缺失才退回「进度在推进」。汽水用这个。
- .elapsedAdvance：只按「进度在推进」判定，适合不上报 rate 的软件。

control 取值：

- .nowPlayingCLI：先试 nowplaying-cli next，失败再发 MediaRemote 命令（覆盖面最广，推荐）。
- .mediaRemote：直接发 MediaRemote 的 NextTrack 命令，不依赖命令行工具。
- .none：不支持切歌；「下一阕」会明确失败，不谎报成功。

## 5. 引擎替你做的事（行为契约）

- 门禁：只有系统正在播放的 bundle 解析出的音源在「已启用集合」内，才参与录制/挂机。未知或未启用的软件一律忽略（fail-closed），并有诊断日志。
- 确认与去抖：标题按该源 confirmTicks 稳定后才触发收卷+换文件+入列；切歌瞬间的抖动不会误触发。
- 挂机监听：启用源开播自动开录；停播（含切到非启用源）满 6 秒自动收卷。
- 歌词链：本地后端（零联网）→ 自建缓存 → LRCLIB → 网易云；抓到即回写自建缓存；离线只走本地后端与自建缓存。
- 旁挂 .lrc：经后端的 lrc() 写入，与自建缓存/在线链一致。
- 落盘/命名/标签：与该音源无关，全链路不变。

## 6. 自测与验收清单

- [ ] swift build --disable-sandbox 通过，无新警告。
- [ ] LefuCore 纯逻辑有单测（bundle 解析、过滤等）；本机若为 CLT-only，swift test 不可用，以 CI（Xcode 15.4）为准。
- [ ] 设置页出现该音源，可开可关；默认是关。
- [ ] 该软件播放时能自动识别（设置里开启后开播自动录）。
- [ ] 切歌：确认节奏符合预期，收卷/换文件/入列正确。
- [ ] 歌词：若实现了本地后端，离线也能出词；旁挂 .lrc 在实现 lrc() 时出现。
- [ ] 停播：切换/退出后 6 秒内自动收卷。
- [ ] 至少完整录一首，确认 MP3/封面/标签/命名与其它源一致。

## 7. 已知限制与后续项

- exposesElapsed/exposesDuration 目前只入档、未接 UI；进度显示仍是「半路接入显示 --:--、否则按估算」。接下一个源前应完成接线（见规格 §10）。
- 只实现 document() 的后端不会产出本地 .lrc 旁挂。
- currentLyricBackends 与行的 sourceName 是会话级的；若一个 WAV 因轮转异常混入多个来源，可能串源。当前单源无影响。
- 轮询间隔取自「第一个启用的音源」，多源且间隔不同时非当前在播源。
- 若系统兜底通道不带 bundle 键，会 fail-closed（保守不录）；已有诊断日志，可在日志里确认。

## 8. 不要做的事

- 不要在引擎（NowPlaying / Lyrics / SessionController / Cutter）里写具体 bundle 或软件分支。
- 不要为补**歌名/歌手/专辑**等元数据去解析软件的私有数据库/私有接口；这些一律用系统「正在播放」。唯一例外是封面：仅当系统不上报、而软件本地有封面时，才用 §3.4 的本地封面提供者兜底。
- 不要把 enabledByDefault 设为 true，避免用户误录视频/播客。
- 不要改动录制、切分、编码、命名策略。

## 9. 模板速查

    Sources/Lefu/Sources/YourNameSource.swift              # 档案（必填）
    Sources/Lefu/Engine/YourNameLocalLyricsBackend.swift   # 本地歌词（可选）
    Sources/Lefu/Engine/YourNameLocalArtwork.swift         # 本地封面兜底（可选）
    Sources/Lefu/Sources/MusicSource.swift                 # 登记处加一行（必填）

参考实现：

- 本地歌词：Sources/Lefu/Sources/SodaSource.swift 与 Sources/Lefu/Engine/SodaLocalLyricsBackend.swift
- 本地歌词（加密 .krc，可逐字）：Sources/Lefu/Sources/KuGouSource.swift、Sources/Lefu/Engine/KuGouLocalLyricsBackend.swift
- 本地歌词（加密 .lrcx）+ 本地封面兜底：Sources/Lefu/Sources/KuwoSource.swift、
  Sources/Lefu/Engine/KuwoLocalLyricsBackend.swift、Sources/Lefu/Engine/KuwoLocalArtwork.swift
- 本地歌词（Electron localStorage / LevelDB + Snappy，喜马拉雅）：Sources/Lefu/Sources/XimalayaSource.swift、
  Sources/Lefu/Engine/XimalayaLocalLyricsBackend.swift、Sources/Lefu/Engine/LevelDBReader.swift
