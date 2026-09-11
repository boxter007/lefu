<div align="center">
  <img src="docs/banner.png" alt="乐府 Lefu — 汽水音乐 / Apple Music / 网易云音乐 / 酷我音乐 / 酷狗音乐 / 喜马拉雅 / QQ音乐 Mac 内录自动裁曲工具" width="100%">
</div>

# 乐府 Lefu — 汽水音乐 / Apple Music / 网易云音乐 / 酷我音乐 / 酷狗音乐 / 喜马拉雅 / QQ音乐 Mac 内录自动裁曲工具

[![Release](https://img.shields.io/github/v/release/boxter007/lefu?color=e8555f&label=release)](https://github.com/boxter007/lefu/releases)
[![License](https://img.shields.io/badge/license-MIT-3fb950)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-378add)](#环境要求)
[![Swift](https://img.shields.io/badge/Swift-5.9-fa7343)](Package.swift)
[![Stars](https://img.shields.io/github/stars/boxter007/lefu?color=e8555f&label=stars)](https://github.com/boxter007/lefu/stargazers)

**乐府（英文名 Lefu）是一款开源免费的 macOS 应用：在 Mac 上边听汽水音乐、Apple Music、网易云音乐、酷我音乐、酷狗音乐、喜马拉雅或 QQ音乐，边按歌自动录制、裁曲、入库，每首歌自动保存为内嵌封面与标签的 MP3，并附带同步 `.lrc` 歌词文件。** 纯 Swift / SwiftUI 原生开发，无需事后剪辑，切歌即出片，MIT 协议开源。

## 立即开始

| 方式 | 命令 / 链接 |
|---|---|
| 下载安装包 | [Releases](https://github.com/boxter007/lefu/releases/latest) → 下载 `Lefu-v1.0.2.zip`（通用二进制，解压拖入 Applications） |
| Homebrew | `brew install --cask boxter007/lefu/lefu` |
| 自行构建 | 见下方[构建运行](#构建运行) |

三步跑通：装 [BlackHole 2ch](https://existential.audio/blackhole/)（App 内一键装）→ 音频 MIDI 设置里建一次「乐府 通道」多输出设备（30 秒）→ 状态变绿，开始采诗。App 内「指南」页有全程引导。

## 界面预览

| 采诗主界面 | 三步上手指南 |
|---|---|
| ![采诗主界面](docs/screenshots/01-capture.png) | ![三步上手指南](docs/screenshots/02-guide.png) |

## 项目信息速览

| 项目 | 信息 |
|---|---|
| 名称 | 乐府（Lefu） |
| 类型 | macOS 音乐内录 / 自动裁曲 / 音乐归档工具 |
| 平台 | macOS 13.0+（Apple Silicon 与 Intel） |
| 技术栈 | Swift 5.9 · SwiftUI · CoreAudio · LAME |
| 内录对象 | 汽水音乐、Apple Music（macOS 自带「音乐」）、网易云音乐、酷我音乐、酷狗音乐、喜马拉雅、QQ音乐（含本地与在线歌曲） |
| 输出格式 | MP3 320kbps（内嵌 ID3 封面标签）+ `.lrc` 同步歌词 |
| 许可证 | [MIT](LICENSE)（开源免费） |
| 变更日志 | [CHANGELOG.md](CHANGELOG.md) |
| 路线图 | [docs/ROADMAP.md](docs/ROADMAP.md) |
| 依赖 | [BlackHole 2ch](https://existential.audio/blackhole/)（App 内一键安装）、LAME（已内置，无需 Homebrew） |

## 核心功能

- **实时裁歌**：逐首录制架构，切歌瞬间自动分段，一首一收卷，不产生"散落的长录音"
- **歌词四路抓取**：音源本地（汽水 / 酷狗 KRC、酷我 `.lrcx`、喜马拉雅字幕，均逐字）→ 自家缓存 → LRCLIB → 网易云，抓到即存缓存，离线也有
- **挂机监听**：菜单栏常驻，开播自动采诗，停播自动收卷，全程无人值守
- **成品即发布级**：LAME 320k 编码，ID3 封面标签内嵌（系统不上报封面时自动从音源本地补齐，如酷我），成品旁挂同步歌词
- **府库一目了然**：按日期归档，App 内直接看今日成果与最近入库

## 环境要求

- macOS 13.0+
- Swift 5.9（Xcode 15+ 或 Swift.org 工具链）
- [BlackHole 2ch](https://existential.audio/blackhole/)（App 内可一键下载安装）
- 汽水音乐、Apple Music、网易云音乐、酷我音乐、酷狗音乐、喜马拉雅或 QQ音乐（内录对象）

## 构建运行

**不想自己编译？** 到 [Releases](https://github.com/boxter007/lefu/releases) 下载 `Lefu-vX.Y.Z.zip`（通用二进制，arm64 + Intel 双架构），解压拖进 Applications 即可。每次发布 tag 都由 GitHub Actions 自动构建。

自己构建：

```bash
git clone <本仓库>
cd lefu
swift build            # 日常开发
bash scripts/build_app.sh        # 组装 build/.dist/乐府.app（本机架构）
UNIVERSAL=1 bash scripts/build_app.sh   # 通用二进制（arm64 + Intel，纯 CLT 即可）
bash scripts/install.sh          # 安装到 /Applications 并校验签名
open build/.dist/乐府.app
```

## 常见问题（FAQ）

**Q：乐府是什么？**
乐府（Lefu）是一款开源免费的 macOS 应用，用于在 Mac 上边听汽水音乐、Apple Music、网易云音乐、酷我音乐、酷狗音乐、喜马拉雅或 QQ音乐边按歌自动录制裁曲，每首歌自动保存为内嵌封面标签的 MP3 并附带同步歌词。

**Q：乐府怎么把汽水音乐 / Apple Music / 网易云音乐 / 酷我音乐 / 酷狗音乐 / 喜马拉雅 / QQ音乐的歌曲保存成 MP3？**
乐府通过 BlackHole 虚拟声卡采集播放器的系统音频输出，按切歌点自动分段，每段经 LAME 320k 编码为 MP3，内嵌 ID3 封面与标签，输出到 `~/Music/乐府` 按日期归档。

**Q：乐府免费吗？开源吗？**
免费且开源，MIT 许可证，源码全部在本仓库，可自行构建或修改。

**Q：乐府需要安装什么依赖？**
只需 BlackHole 2ch 虚拟声卡（App 内一键下载安装）。MP3 编码器（LAME）已内置在 App 中，无需 Homebrew。

**Q：为什么需要 BlackHole？**
乐府靠虚拟声卡采集系统正在播放的音频。配合「乐府 通道」多输出设备，同一份声音同时进 BlackHole（录制）和扬声器（收听），边听边录互不干扰。

**Q：乐府支持哪些音乐软件？**
已支持 **汽水音乐**、**Apple Music**（macOS 自带「音乐」）、**网易云音乐**、**酷我音乐**、**酷狗音乐**、**喜马拉雅** 与 **QQ音乐**（本地与在线歌曲/播客均可；Apple Music 广播直播暂未适配）。其中汽水、酷狗、酷我与喜马拉雅支持零联网的本地歌词（汽水 / 酷狗为 KRC 逐字，酷我为 `.lrcx` 逐字时间轴，喜马拉雅为本地字幕文稿，需在 App 内开启「自动打开字幕/歌词」），酷我不上报封面时会自动从本地补齐。采用可扩展的音源架构，后续按需接入更多播放器。接入新音源的方式见 [docs/ADDING-A-SOURCE.md](docs/ADDING-A-SOURCE.md)。

**Q：歌词从哪里来？**
按 音源本地歌词（汽水 / 酷狗 KRC、酷我 `.lrcx`、喜马拉雅文稿，均逐字）→ 自家缓存 → LRCLIB → 网易云 四路顺序抓取，纯器乐或小众歌可能全网没有；联网抓到过的歌会存进缓存，之后离线也有。

**Q：录出来的 MP3 音质如何？**
LAME 320kbps CBR，与源音频同为 44.1kHz 采样率，内嵌 ID3v2.3 封面与标签，旁挂 `.lrc` 同步歌词。

## 依赖致谢

- [LAME](https://lame.sourceforge.io/)（LGPL）—— MP3 编码，随 App 分发 `libmp3lame.dylib`，依 LGPL 2.0/3.0 之授权分发，源码见 [lame.sourceforge.io](https://lame.sourceforge.io/)
- [BlackHole](https://existential.audio/blackhole/) —— 存在性音频的虚拟声卡（GPLv3），由 App 运行时引导用户从官方渠道安装，本仓库不分发其本体

## Star 趋势

[![Star History Chart](https://api.star-history.com/svg?repos=boxter007/lefu&type=Date)](https://star-history.com/#boxter007/lefu&Date)

## 支持项目

如果乐府帮到了你，**给个 Star** 是最实在的支持——它能让更多在 Mac 上听歌的人找到这个工具。也欢迎把这篇文章转给有同样需要的朋友。

## License

[MIT](LICENSE)
