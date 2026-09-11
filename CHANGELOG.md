# 变更日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)；条目组织参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
构建号由打包脚本自动递增（见 [`VERSION`](VERSION) 与 [`scripts/build_app.sh`](scripts/build_app.sh)），应用内「设置 → 引擎（高级）→ 版本」可查看当前安装的版本。

## [1.0.2] — 2026-09-11

底层加固：安装链路补上完整性校验、日志加上容量上限、签名去掉废弃用法并纳入校验。不涉及界面与录制逻辑。

### 安全

- **安装包双重校验**（[#9](https://github.com/boxter007/lefu/issues/9)）：`BlackHoleInstaller` 下载官方 pkg 后，先比对字节级 SHA256，再经 `pkgutil --check-signature` 核验「Developer ID Installer: Existential Audio Inc. (Q5C99V536K)」签名链且已被 Apple 公证；任一不过即中止，不再进入提权安装。此前只有「响应码 200 + 大小 > 100KB」两道形同虚设的门

### 修复

- **诊断日志无上限**（[#10](https://github.com/boxter007/lefu/issues/10)）：单文件超过 2MB 即归档为 `lefu-diag.log.1`（覆盖式，不堆叠）。挂机常驻不再会一路写大；顺带把每次调用新建的 `DateFormatter` 提为静态复用
- **签名流程规范化**（[#11](https://github.com/boxter007/lefu/issues/11)）：去掉已废弃的 `codesign --deep`，改为显式签 `Contents/Frameworks` 内的 dylib 再签主 bundle；签名失败不再被 `|| true` 静默吞掉，`codesign --verify --strict` 不过就中止打包
  - 注：`--options runtime`（hardened runtime）**本版刻意不加**——实测 ad-hoc 签名无 Team ID 时启用它会触发 library validation，拒绝 `dlopen` 内置 libmp3lame，导致 MP3 编码静默回落 M4A。须随 [#2](https://github.com/boxter007/lefu/issues/2) 的真实证书一起启用

### 构建

- **仓库卫生**（[#12](https://github.com/boxter007/lefu/issues/12)）：`design/` 下 6 个图标生成的临时中间产物（约 4MB）移出版本控制并加 `.gitignore` 规则
- **Homebrew tap 自动化**：新增 [`scripts/bump_cask.sh`](scripts/bump_cask.sh)，按发布版本同步 `boxter007/homebrew-lefu` 的 cask 版本号与 sha256；发布流程加了 `Bump Homebrew cask` 一步，配置 `TAP_TOKEN` 后自动执行，不再靠手工同步（此前 cask 曾落后一个版本）

## [1.0.1] — 2026-09-11

这一版主要治「长时间挂机录制越跑越卡」的性能病，另修列表定位与波形渲染两处回归，并补上版本号体系。

### 修复

- **长时间录制后 CPU 长期占满、界面卡顿**（[#4](https://github.com/boxter007/lefu/issues/4)）：电平值拆到独立的 `LevelMeter` 并对发布节流，会话队列 `VStack` → `LazyVStack`（`290e2db`）；呼吸/脉冲动效与电平波形改由 Core Animation 层动画直驱，消除 `.repeatForever` 动画引发的 60Hz 逐帧全树布局（`b538aab`）
- **关闭主窗口后重新打开，曲目列表回到顶部、不跟随正在采录的行**（[#5](https://github.com/boxter007/lefu/issues/5)）：重开时主动滚动到当前采录行，并兼顾 `LazyVStack` 首帧未铺好的情况（`290e2db`）
- **波形柱状图生长方向与渐变色序错误**（[#6](https://github.com/boxter007/lefu/issues/6)）：改回底对齐向上生长，渐变色序还原为 accent 在下、live 在上（`33521a1`）
- **曲目序号列在 100 首以上折行、新增行不自动滚动到底部**（[#7](https://github.com/boxter007/lefu/issues/7)）：序号列宽按位数自适应；行数增长时滚动到最新行（`66111dc`）

### 新增

- **版本号体系**（[#8](https://github.com/boxter007/lefu/issues/8)）：`VERSION` 文件记录营销版本与构建号，打包时构建号自动 +1 并注入 `Info.plist`；设置页与诊断日志展示当前版本（`8b5625e`、`d9a6430`）

### 构建

- 新增 [`scripts/install.sh`](scripts/install.sh)：安装到 `/Applications` 后自动校验代码签名并打印装后版本号，同时提示「应用正在运行时需退出重开才会加载新版本」
- `APP_VERSION` 环境变量仍可覆盖营销版本号，与 [`.github/workflows/release.yml`](.github/workflows/release.yml) 的发布流程兼容

## [1.0.0] — 2026-09-10

首个公开发行版。

- 汽水音乐 Mac 版内录，切歌瞬间自动分段，一首一收卷
- 歌词四路抓取：自家缓存 → 汽水本地 → LRCLIB → 网易云
- LAME 320k 编码，ID3 封面与标签内嵌，旁挂同步 `.lrc`
- 菜单栏挂机监听：开播自动采诗，停播自动收卷
- 府库按日期归档，应用内查看今日成果与最近入库

[1.0.2]: https://github.com/boxter007/lefu/releases/tag/v1.0.2
[1.0.1]: https://github.com/boxter007/lefu/releases/tag/v1.0.1
[1.0.0]: https://github.com/boxter007/lefu/releases/tag/v1.0.0
