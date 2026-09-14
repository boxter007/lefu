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

  # ⚠️ 必须是范围为字符串 ">= :ventura" 的写法。
  #
  # 原来是 `depends_on macos: :ventura`（单个符号），Homebrew 会把它理解为
  # **精确匹配 Ventura 这一个版本**，而不是「Ventura 及以上」。后果是
  # Sonoma / Sequoia 用户安装时直接报：
  #     Error: This software does not run on macOS versions other than Ventura.
  # 即「除了 Ventura 以外都不行」——这正是用户反馈的装不上问题的根因。
  #
  # 乐府实际支持 macOS 12（Monterey）起，故这里写 >= :monterey。
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
