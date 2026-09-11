# 乐府 · 路线图

> 最后更新：2026-09-11 ｜ 当前版本：v1.0.2
> 关联文档：[DESIGN.md](../DESIGN.md)（UI 规范）、[CHANGELOG.md](../CHANGELOG.md)（已发布内容）

本路线图取代 DESIGN.md §9 的分期清单——那份清单的一期/二期/三期已基本落地（录制台、设置页、挂机监听、菜单栏、手动打点均已完成），剩下的空缺归入下方各版本继续推进。

## 两个支柱（2026-09-11 晶晶定）

1. **界面美化** —— 把 DESIGN.md 承诺、但代码里没兑现的视觉真正做出来
2. **多音源** —— 从「汽水音乐专用」走向「支持多个音乐播放软件」

## 总览

| 版本 | 主题 | 状态 | 一句话 |
|---|---|---|---|
| v1.0.2 | [安装链路加固与健壮性](https://github.com/boxter007/lefu/milestone/2) | ✅ 已发布 | 修底层，不动界面 |
| **v1.0.3** | [分发可用性修复](https://github.com/boxter007/lefu/milestone/3) | 🚧 进行中 | Intel 机器上 MP3 编码不可用 |
| **v1.1** | [界面美化](https://github.com/boxter007/lefu/milestone/4) | 📋 规划中 | 把「封面即氛围」和卡拉OK 真正做出来（#14–#18） |
| **v1.2** | [多音源](https://github.com/boxter007/lefu/milestone/5) | 📋 规划中 | 支持多个音乐播放软件，不再只认汽水（#19–#24） |
| **v1.3** | [分发与可信赖](https://github.com/boxter007/lefu/milestone/6) | 📋 规划中 | 签名公证、应用内更新、英文 README（#1–#3、#25–#26） |

排序理由：v1.0.3 是已发现的功能性缺陷，必须先修；v1.1 兑现既定设计承诺、纯收益无风险；v1.2 是产品定位的扩展，改动面小但牵涉 UI、歌词源与切歌判定；v1.3 是已经开过 issue 的工程欠条。

---

## v1.0.3 — 分发可用性修复

已发布包是「通用二进制」，但内置的 `libmp3lame.0.dylib` 是从 Apple Silicon 的 Homebrew 直接拷来的 arm64 单架构，Intel 机器 `dlopen` 会报 `incompatible architecture`，MP3 编码静默回落到 M4A——用户以为存的是 MP3。

| # | 事项 | 说明 |
|---|---|---|
| [#13](https://github.com/boxter007/lefu/issues/13) | 内置 LAME 补齐双架构 | 用 `lipo` 合并 arm64 + x86_64，或 CI 里两架构分别编译后合并；打包脚本加一道「dylib 架构必须匹配宿主包架构」的校验，防止再退化 |
| — | CI 加架构自检 | 发布前断言 `lipo -archs` 与主程序一致，不一致直接 fail，不再靠人工发现 |
| — | 引导文案兜底 | 万一编码器不可用，设置页「引擎（高级）」的自检应把 LAME 标红并给出手动安装指引，而不是静默回落 |

---

## v1.1 — 界面美化

DESIGN.md 把「封面即氛围」和「卡拉OK 逐字」写成了设计原则，但代码里都只做了个意思。这一版把它们兑现，并把成品从「一次性产出」变成可回味的资产。

| # | 事项 | 现状 / 落点 |
|---|---|---|
| [#14](https://github.com/boxter007/lefu/issues/14) | **封面驱动主题取色** | 现在 `RecordView.swift` 的 `artColor` 只是把 `track.key` 哈希进 `[accent, live, ok]` 三色表——跟封面毫无关系。改为真从 `session.artworkImage` 提取主色（`CIImage` + `CIAreaAverage`，或轻量 k-means），按 `track.key` 缓存；灰阶/低饱和封面回落默认粉。取色结果带动强调色、波形 active 柱、REC 呼吸点、状态徽章、背景光晕 |
| [#15](https://github.com/boxter007/lefu/issues/15) | **卡拉OK 逐字高亮** | `SodaLyrics.krcToLrc` 现在把 KRC 的 `<偏移,长>` 词段信息直接丢掉，降级成整行 LRC，所以歌词只能整行切换。改为保留词段时间轴，按刻逐字点亮（当前行其余字半透明） |
| [#16](https://github.com/boxter007/lefu/issues/16) | **曲库页（封面墙 + 内置播放）** | DESIGN.md §2 一直挂着「占位，v2 再启用」，实际上连占位页都没有，导航只有采诗/设置/指南。改为可用：按专辑/日期分组的封面墙、点击即播、右键重裁 / 转格式 / 在访达显示。这是把「府库」名副其实 |
| [#17](https://github.com/boxter007/lefu/issues/17) | **视觉层次打磨** | 标题栏 `regularMaterial` + 侧轨 `ultraThinMaterial` 的材质关系再收一层；补齐空态与加载态；深浅双主题逐项过一遍对比度（正文 ≥ 4.5:1，辅助文字 ≥ 3:1） |
| [#18](https://github.com/boxter007/lefu/issues/18) | **动效收口** | 对照 DESIGN.md §5 逐条核：换歌滑入、歌词整行过渡、停止按钮进度态、完成通知。缺的补上，多余的砍掉 |

---

## v1.2 — 多音源（支持多个音乐播放软件）

### 为什么改动面比想象中小

乐府的内录链路本身**与平台完全无关**：BlackHole 抓的是系统声音，静音切分是纯音频判断，LAME 编码、ID3 标签、封面内嵌都不关心声音从哪来。真正的耦合点只有三处，而且都在表层：

| 耦合点 | 位置 | 现状 |
|---|---|---|
| 音源白名单 | `NowPlaying.swift` | `sodaBundle = "com.soda.music"` **硬编码**，非汽水一律丢弃 |
| 歌词获取 | `SodaLyrics.swift` | 读汽水本地 MessagePack 缓存里的 KRC——**只有汽水有** |
| 切歌判定 | `SessionController.swift` | 确认/去抖/残影识别是按汽水的上报节奏调出来的 |

也就是说，**把白名单放开，非汽水就已经能录**——缺的是歌词与切歌稳准。这是典型的「改动小、价值大」。

### 事项

| # | 事项 | 说明 |
|---|---|---|
| [#19](https://github.com/boxter007/lefu/issues/19) | **音源白名单可配置** | 改为可勾选列表：汽水音乐 `com.soda.music`、网易云 `com.netease.163music`、QQ音乐 `com.tencent.QQMusic`、Apple Music `com.apple.Music`、Spotify `com.spotify.client` 等。**默认仍保持「仅汽水」**，避免误录到视频/播客；含多播放器同时播放的归属策略 |
| [#20](https://github.com/boxter007/lefu/issues/20) | **通用歌词链路（LRCLIB 优先）** | 非汽水没有本地 KRC。改为按 `标题 + 歌手 + 时长` 匹配走 LRCLIB → 网易云（`Lyrics.swift` 已有这条路，需要把它从「兜底」提为「主路」并补匹配精度与逐字格式映射） |
| [#21](https://github.com/boxter007/lefu/issues/21) | **切歌确认器档案化** | 现在 `SessionController` 的确认器参数是照汽水调的（确认延迟、残影识别窗口）。改为按音源取参数集，并提供「自动学习」：首场录制时观察该音源的实际上报节奏。含无 KRC 时的边界策略分档 |
| [#22](https://github.com/boxter007/lefu/issues/22) | **设置页新增「音源」分区** | 勾选允许的播放器 + 每源开关（是否参与挂机自动采诗）+ 归属策略；采诗页与成品标签标注来源平台 |
| [#23](https://github.com/boxter007/lefu/issues/23) | **引导与文案泛化** | `GuideView.swift` 全篇是汽水引导（"打开汽水音乐"），需泛化成"打开你的音乐软件"；README 与落地页的产品定位从"汽水音乐内录工具"改为多平台 |
| [#24](https://github.com/boxter007/lefu/issues/24) | **各音源实测矩阵** | 逐平台记录：曲目信息完整度、封面有无、歌词命中率、切歌判定准确率。这是 v1.2 能否宣称"支持"的依据 |

### 边界（先不做）

- **浏览器网页音乐**（B站 / YouTube / 网页版网易云）：now playing 归属与元数据质量不可控，默认排除在推荐白名单之外，只在文档里说明"技术上能录但不保证切分"
- **非音乐类音源**（播客、视频、会议软件）：不做适配

---

## v1.3 — 分发与可信赖

已经开过 issue 的工程欠条，收口即可。不追求新功能，只求「下载—安装—升级」这条链路对普通用户不再有坎。

| # | 事项 | 说明 |
|---|---|---|
| [#2](https://github.com/boxter007/lefu/issues/2) | **正式签名与公证** | Developer ID 证书 + Apple 公证，消除 Gatekeeper 拦截。**同时解锁 hardened runtime**（v1.0.2 因 ad-hoc 会打断 `dlopen` 而刻意未启用，见 CHANGELOG） |
| [#3](https://github.com/boxter007/lefu/issues/3) | **应用内更新检查** | 启动/菜单栏检查新版本，提示并一键跳转或下载 |
| [#1](https://github.com/boxter007/lefu/issues/1) | **英文 README 与英文落地页** | 覆盖海外用户，配套英文截图 |
| [#25](https://github.com/boxter007/lefu/issues/25) | **国内可用下载通道** | 落地页直连下载 + 展示 sha256；或接国内对象存储/CDN。GitHub Releases 在国内不稳 |
| [#26](https://github.com/boxter007/lefu/issues/26) | **Mac App Store 可行性评估** | 沙盒限制与内录、MediaRemote 私有框架、屏幕录制权限存在冲突，需先做技术验证再决定；若不可行，结论写进文档并转向独立分发 |

---

## 候选 / 待议

尚未排期，也可能穿插进上面任一版本：

- **音频路由 CFString 泄漏**：`AudioRouting` 中 `AudioObjectGetPropertyData` 读 `kAudioObjectPropertyName` / `DeviceUID` 返回的 CFString 是 +1 引用，代码从不释放，每次调用漏一个
- **聚合子设备判断退化**：`AudioRouting` 里 `bhUID` 取了却没用，判断退化成名字前缀 `hasPrefix("BlackHole")`——装了 16ch/64ch 变体会误判
- **批量格式转换**（DESIGN.md 二期）：MP3 / M4A / WAV 互转，右键或拖拽
- **崩溃恢复完整链路**（DESIGN.md 一期）：目前只清理孤儿 session 目录，尚缺「有 WAV 无成品 → 提示一键重裁」
- **曲目元数据编辑**：成品库里直接改歌名/歌手/封面并回写标签
- **命名模板**（DESIGN.md 三期）：`{歌手} - {歌名}` / `{日期} {歌名}` / `{专辑}` 自由组合

## 已完成（存档）

| 版本 | 内容 |
|---|---|
| v1.0.0 | 首个公开版本：采诗、裁曲、逐首录制、四路歌词、挂机监听、菜单栏 |
| v1.0.1 | 长时间挂机性能病、列表定位与波形渲染回归、版本号体系 |
| v1.0.2 | 安装包双重校验、日志容量上限、签名流程规范化、Homebrew cask 自动化 |
