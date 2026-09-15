# 变更日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)；条目组织参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。
构建号由打包脚本自动递增（见 [`VERSION`](VERSION) 与 [`scripts/build_app.sh`](scripts/build_app.sh)），应用内「设置 → 引擎（高级）→ 版本」可查看当前安装的版本。

## [1.0.5] — 2026-09-15

兼容性与安装体验：最低支持版本从 macOS 13 降到 **macOS 12**，修掉「低版本装不上」与「MP3 静默变 M4A」两个问题。

### 修复

- **Homebrew 安装被拦**：cask 里的 `depends_on macos: :ventura` 是**精确匹配 Ventura 这一个版本**（而非「Ventura 及以上」），导致 Sonoma / Sequoia 用户安装直接报
  `Error: This software does not run on macOS versions other than Ventura.`
  改为 `depends_on macos: ">= :monterey"`
- **MP3 静默回落 M4A**（[#13](https://github.com/boxter007/lefu/issues/13)）：内置的 `libmp3lame.0.dylib` 此前直接拷贝构建机的 Homebrew 产物，会带上构建机的 SDK minos（实测 macOS 26 上是 `26.0`）。在低于该版本的机器上 `dlopen` 必然失败，而失败路径是**静默回落 M4A**——用户拿不到 MP3，界面还不报错。现在改为**从 LAME 官方源码、以 `-mmacosx-version-min` 自行编译**，让目标版本由我们决定而非构建机决定
- **universal 包里的 dylib 只有 arm64**（[#13](https://github.com/boxter007/lefu/issues/13)）：主程序是 arm64 + x86_64 而内置 dylib 只有 arm64，Intel 机器上 `dlopen` 报 `incompatible architecture`，MP3 编码完全不可用。现在 `UNIVERSAL=1` 时按架构各编一次再 `lipo` 合并

### 新增

- **最低支持 macOS 12 (Monterey)**（原为 macOS 13）。实现上刻意**不做版本分叉**：主窗一律 `WindowGroup`、菜单栏一律 AppKit 的 `NSStatusItem` + `NSPopover`（`Views/MenuBarBridge.swift`），于是全应用只有一条代码路径
  - 为什么不按版本分叉：`SceneBuilder` 没有 `buildEither`，Scene 内部不能写 `if`；改用普通函数 + `some Scene` 也不行——opaque 返回类型要求所有 return 的底层类型一致，而 `Window` 与 `WindowGroup` 是不同类型。编译器不报错却生成会崩的代码，实测启动即段错误（`EXC_BAD_ACCESS` / `swift_retain` ← `initializeWithCopy for LefuSceneContent`）。收敛成单一路径后该问题从根上消失，也让 macOS 12 的行为第一次真正可测
  - 面板本体 `MenuBarPanel` 是普通 SwiftUI View，界面代码零重复；主题派生抽成 `Views/LefuThemeFactory.swift` 供主窗与面板共用，避免面板丢失封面强调色
  - 主窗关闭由 `Views/MainWindowKeeper.swift` 转为「隐藏」，因此无需 macOS 13+ 的 `openWindow` 也能重新打开
- **一键安装脚本** [`scripts/install_remote.sh`](scripts/install_remote.sh)：
  `curl -fsSL https://raw.githubusercontent.com/boxter007/lefu/main/scripts/install_remote.sh | bash`
  macOS 的隔离标记由「下载它的程序」打上，`curl` 不会打，故这样安装**无需右键、无需进系统设置、无需 `xattr`**。顺带避开了中文路径「乐府.app」在复制粘贴时变成乱码的坑
- **打包期硬校验**：`build_app.sh` 现在**逐个架构**断言主程序与 `libmp3lame` 的 `minos` 不高于目标版本，并校验 universal 构建的架构完整性，不达标即中止（把「静默降级」变成「构建期失败」）。CI 同步修掉两处缺陷：一致性检查因 `grep -o '[0-9.]*<'` 的零长度匹配而必然失败，以及 `otool -l` 不带 `-arch` 时只检查 fat 包中第一个架构

### 变更

- 安装文档全面修订：「右键 → 打开」在 **macOS 15 (Sequoia) 已被 Apple 移除**，四处旧说法（README、官网、cask caveats、发布说明）统一改为正确的放行路径，并把命令行安装提到首位

## [1.0.4] — 2026-09-13

录制体验收尾：把「府库已有」的判断统一并扩到整个曲库，新增自动切歌；同时给录音补上响度归一化，并修掉主窗恢复与电平表两个恼人的问题。

### 新增

- **已有歌自动下一首**：设置 → 录制，默认开启。录到府库里已有的歌时，自动让当前音源切到下一首，不再把整首已拥有的歌录完再丢；关掉则只标「跳过」继续往下录
- **`LibraryIndex` 统一「库中已有」判定**：递归整个输出目录（历次日期目录、裁曲、用户导入的专辑），按 `艺术家 - 歌名` 精确比对；行徽章与落盘跳过改用同一判定，修掉此前「歌名子串」与「精确路径」两套规则打架的问题
- **录音响度归一化**：每段按整段 RMS 提到目标响度（-16dBFS，增益上限 +40dB，保证不削顶）。BlackHole 收到的电平随系统输出音量变化，此后不论音量大小，成品音量都稳定

### 修复

- 主窗改为单实例 `Window`：关闭后可从菜单栏「打开主窗」或点程序坞图标重新打开，不再「关掉就回不来」
- 电平表改为相对 AGC 映射：BlackHole 电平偏低时，波形与迷你电平条也能正常跳动
- 修「一首歌一直转换中」：裁切阶段改为单调推进，晚到的中间态不再覆盖已完成的终态
- 修扩展名图标把 `MP3` 当 SF Symbol 引起的 SwiftUI 报错

## [1.0.3] — 2026-09-11

从「只支持汽水音乐」升级为可扩展的多音源架构，一次接入五个新音源，并把音源开关搬进设置页。

### 新增

- **多音源 Provider 架构**：音源档案（Bundle ID / 检测 / 控制 / 歌词后端 / 本地封面）纯数据化，登记处统一门禁与调度，新增音源只需一个档案文件加一行注册
- **五个新音源**：网易云音乐、酷我音乐、酷狗音乐、喜马拉雅、QQ音乐（均经 MediaRemote 取元信息、封面与播放位置）
- **本地歌词**：酷我 `.lrcx`（逐字时间轴）、酷狗 KRC（逐字）、喜马拉雅本地字幕文稿（逐字），零联网
- **本地封面兜底**：系统不上报封面时，酷我自动从本地缓存补齐
- **设置 → 音源**：新增音源分区，多列复选框网格，只录制勾选的软件

### 说明

- QQ音乐本地缓存为加密 QRC，暂未接入本地歌词，曲目走在线歌词链（LRCLIB / 网易云）
- 喜马拉雅本地歌词需在 App 内开启「自动打开字幕/歌词」

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

[1.0.3]: https://github.com/boxter007/lefu/releases/tag/v1.0.3
[1.0.2]: https://github.com/boxter007/lefu/releases/tag/v1.0.2
[1.0.1]: https://github.com/boxter007/lefu/releases/tag/v1.0.1
[1.0.0]: https://github.com/boxter007/lefu/releases/tag/v1.0.0
