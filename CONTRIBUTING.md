# 参与贡献

感谢你愿意为乐府出力。这个项目围绕一个很具体的场景构建：**在 Mac 上边听汽水音乐，边把每首歌按首切好、归档成带封面与歌词的 MP3。** 所有改动都请围绕这个场景判断价值。

## 先跑起来

```bash
git clone git@github.com:boxter007/lefu.git
cd lefu
swift build                 # 日常开发
bash scripts/build_app.sh   # 组装 build/.dist/乐府.app（本机架构）
bash scripts/install.sh     # 安装到 /Applications 并校验签名
open build/.dist/乐府.app
```

开发时需要准备：

- macOS 13.0+
- Swift 5.9（Xcode 15+ 或 Swift.org 工具链）
- [BlackHole 2ch](https://existential.audio/blackhole/)（调试内录必需）
- 音频 MIDI 设置里建好「乐府 通道」多输出设备（名字一字不差，否则 App 认不出来）

首次启动会被 Gatekeeper 拦截（ad-hoc 签名），右键 App 选「打开」即可，或 `xattr -cr build/.dist/乐府.app`。

## 提交改动

1. **先开 issue 再动手**。对于非小修的改动，先说清楚你要解决什么问题，避免写完发现方向不对。
2. 从 `main` 签出分支，分支名用 `fix/xxx` 或 `feat/xxx`。
3. 提交前确保 `swift build` 通过，涉及编码/切段的改动请附上实际产出的 MP3 验证结果。
4. **每个提交只做一件事**，提交信息第一行 50 字符内，说清"改了什么"。

提交信息示例：

```
修复静音跳过阈值在多声道下的误判
Cutter 增加 WAV 头长度校验，防越界崩溃
```

## 代码约定

- Swift 5 语言模式，遵循仓库现有风格（2 空格缩进，类型名 UpperCamelCase，方法名 lowerCamelCase）
- **跨队列回调必须强持有派发块**。这是踩过的坑：`[weak self]` 派发 + 局部变量持有，GCD 块结束的同一毫秒就释放，主队列回调会静默消失，极难排查
- 失败要有明确反馈，**不允许静默丢中间产物**（统一清理通道参照现有实现）
- 新增中文界面文案请沿用[命名词汇表](README.md#命名词汇表)的语汇：采诗、收卷、下一阕、府库

## 不要做的事

- 不要尝试 hack macOS 系统私有接口去程序化创建多输出设备。这条路径已被验证走不通（`AudioHardwareCreateAggregateDevice` 建出来的是通道拼接），项目选择引导用户手工建一次，而不是绕过系统限制
- 不要引入 Homebrew 之外的额外运行时依赖。LAME 已内置，这是刻意设计
- 不要在代码、文档、commit 信息中出现"下载会员歌曲""破解"这类表述。乐府是**个人音频归档工具**，内录对象是用户自己正在收听的音频流

## 报告问题

请用仓库的 [issue 模板](https://github.com/boxter007/lefu/issues/new/choose)，附上：

- macOS 版本与芯片类型（Apple Silicon / Intel）
- 汽水音乐版本号
- 复现步骤，以及预期结果与实际结果
- 相关日志或截图

## License

贡献的代码将按 [MIT 协议](LICENSE) 授权。
