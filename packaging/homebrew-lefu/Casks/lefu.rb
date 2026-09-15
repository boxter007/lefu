cask "lefu" do
  version "1.0.4"
  sha256 "7778851b15d214ddef34fee43e52f7d746d57cd2dd5797443cb68886c25084e4"

  url "https://github.com/boxter007/lefu/releases/download/v#{version}/Lefu-v#{version}.zip",
      verified: "github.com/boxter007/lefu/"
  name "乐府"
  desc "Music archiver: per-song recording and tagging for Soda Music on macOS"
  homepage "https://github.com/boxter007/lefu"

  livecheck do
    url :url
    strategy :github_latest
  end

  # ⚠️ 这里**必须**写成范围字符串，不能图省事改成单个符号 :monterey。
  #    改动前请先读完这段，否则会把一个已经修好的线上问题改回去。
  #
  # 【问题】原来写的是 `depends_on macos: :ventura`（单个符号）。
  #   在 Homebrew ≤ 5 里，单个符号的语义是**精确匹配**，源码为证
  #   （brew 4.2.0, cask/dsl/depends_on.rb）：
  #       elsif MacOSVersion::SYMBOLS.key?(args.first)
  #         MacOSRequirement.new([args.first], comparator: "==")   # ← "==" 精确匹配
  #   于是除 Ventura 外的**所有**系统（含更高的 Sonoma / Sequoia）安装时都报：
  #       Error: This software does not run on macOS versions other than Ventura.
  #   这就是用户反馈「装不上」的根因。
  #
  # 【Homebrew 6 变了语义】brew 6 把单个符号改成了 ">="
  #   （cask/dsl/depends_on.rb 固定传 comparator: ">="），于是 Homebrew 6 上
  #   `:monterey` 恰好也等于「12 及以上」，且不再有弃用警告。
  #
  # 【为什么仍然坚持字符串写法】三种写法的实测对照（Homebrew 6.0.15 实测 +
  #   4.2.0 源码核对）：
  #
  #     写法                    Homebrew ≤5        Homebrew 6+        安装期警告
  #     ">= :monterey"          正确（12+）         正确（12+）        有 1 条弃用警告
  #     :monterey               错误！精确匹配 12  正确（12+）        无
  #     （不写）                 可装               可装               无
  #
  #   `:monterey` 在旧版 Homebrew 上会把「12 及以上」变成「只有 12」，
  #   等于把刚修的这个 bug 原样改回去——所以不能选。
  #   「不写」虽然最干净，但失去了 Homebrew 层的兜底，macOS 11 用户会先装成功、
  #   再打不开，体验反而更差（虽然 Info.plist 的 LSMinimumSystemVersion=12.0
  #   会让系统给出提示）。
  #
  #   字符串写法的代价只是**一条弃用警告**（不影响安装，brew audit 也通过）。
  #   这是刻意用一点噪音换「任何 Homebrew 版本上都正确」，符合「最大化兼容」。
  #
  # 【将来何时可以改成 :monterey】当确认用户群已无 Homebrew ≤ 5
  #   （即 Homebrew 6 普及）之后。届时改一行即可，警告也会消失。
  #   在那之前请不要改。
  depends_on macos: ">= :monterey"

  app "乐府.app"

  caveats <<~EOS
    乐府使用 ad-hoc 签名（未经 Apple 公证），首次启动可能被 Gatekeeper 拦下。

    macOS 13 ~ 14 放行方式：
      · 在「访达 → 应用程序」中右键点乐府，选择「打开」并确认。

    macOS 15 (Sequoia) 及以上：Apple 已移除「右键 → 打开」的绕过方式，请改用
      · 「系统设置 → 隐私与安全性」，拉到最下方，点「仍要打开」并确认。

    若不想处理以上任何步骤，推荐改走命令行安装（不会带上隔离标记，可直接打开）：
      curl -fsSL https://raw.githubusercontent.com/boxter007/lefu/main/scripts/install_remote.sh | bash

    首次使用需安装 BlackHole 虚拟声卡，乐府内可一键安装。
  EOS

  zap trash: [
    "~/Library/Application Support/com.jingjing.lefu",
    "~/Library/Caches/com.jingjing.lefu",
    "~/Library/Preferences/com.jingjing.lefu.plist",
    "~/Library/Saved Application State/com.jingjing.lefu.savedState",
  ]
end
