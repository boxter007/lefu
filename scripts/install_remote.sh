#!/bin/bash
# install_remote.sh — 面向普通用户的一键安装脚本
#
# 用法（README / cask caveats 里推广的就是这一行）：
#   curl -fsSL https://raw.githubusercontent.com/boxter007/lefu/main/scripts/install_remote.sh | bash
#
# 为什么需要它 —— 这是「安装尽可能简易」的关键：
#   macOS 的隔离标记（com.apple.quarantine）是**下载它的那个程序**打上的。
#   浏览器下载 → 带标记 → 未公证的 App 会被 Gatekeeper 拦下；
#   而 curl 不会打这个标记 → 未公证也能直接双击打开。
#   所以走命令行安装的用户，不需要右键、不需要进系统设置、不需要 xattr。
#
#   顺带避开了另一个坑：中文路径「乐府.app」在复制粘贴时容易变成乱码
#   （真实案例：用户粘出来的是 /Applications/RT .app），本脚本不含中文路径参数。
set -euo pipefail

REPO="boxter007/lefu"
APP_NAME="乐府.app"
DEST="/Applications/${APP_NAME}"

say()  { printf '%s\n' "$*"; }
die()  { printf '错误：%s\n' "$*" >&2; exit 1; }

# ---- 1. 系统版本检查 ----
OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VER%%.*}"
if [ "$OS_MAJOR" -lt 12 ]; then
  die "乐府需要 macOS 12 (Monterey) 或更高版本，当前为 ${OS_VER}。"
fi
say "系统 ${OS_VER} ✓"

# ---- 2. 解析要装的版本 ----
say "查询最新版本…"
API="https://api.github.com/repos/${REPO}/releases/latest"
VER="$(curl -fsSL "$API" | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
[ -n "$VER" ] || die "无法获取最新版本号（网络或 GitHub API 限流）。可改用 Homebrew：brew install --cask ${REPO}/${REPO#*/}"
say "最新版本 v${VER}"

URL="https://github.com/${REPO}/releases/download/v${VER}/Lefu-v${VER}.zip"

# ---- 3. 下载并解压到临时目录 ----
TMP="$(mktemp -d)"
trap '/bin/rm -rf "$TMP"' EXIT

say "下载 ${URL}"
curl -fL --progress-bar -o "$TMP/lefu.zip" "$URL" || die "下载失败。"

say "解压…"
ditto -x -k "$TMP/lefu.zip" "$TMP" || die "解压失败。"
[ -d "$TMP/${APP_NAME}" ] || die "压缩包结构异常，未找到 ${APP_NAME}。"

# ---- 4. 安装到 /Applications ----
if [ -w /Applications ]; then
  SUDO=""
else
  say "需要管理员权限写入 /Applications"
  SUDO="sudo"
fi

if [ -d "$DEST" ] && pgrep -x "${APP_NAME%.app}" >/dev/null 2>&1; then
  say "检测到乐府正在运行，先退出…"
  osascript -e 'quit app "乐府"' 2>/dev/null || true
  sleep 2
fi

say "安装到 ${DEST}"
$SUDO /bin/rm -rf "$DEST"
$SUDO ditto "$TMP/${APP_NAME}" "$DEST"

# ---- 5. 关键：清除隔离标记，免去 Gatekeeper 拦截 ----
# curl 本就不会打标记，这里再兜一次底（例如用户之前用浏览器装过旧版，
# 或某些 shell/代理链路会补上标记）。
$SUDO xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

# ---- 6. 校验 ----
if codesign --verify --strict "$DEST" 2>/dev/null; then
  say "签名自校验通过"
fi

INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || echo '?')"
say ""
say "✅ 安装完成：${DEST}（版本 ${INSTALLED}）"
say ""
say "下一步："
say "  1. 打开乐府（已在「应用程序」里，也可执行：open -a 乐府）"
say "  2. 首次使用需装 BlackHole 虚拟声卡，乐府内可一键安装"
say "  3. 再按 App 内「指南」页做一次音频 MIDI 设置（约 30 秒）"
say ""
say "如果打开时仍提示「无法验证开发者」："
say "  macOS 15+ 请到「系统设置 → 隐私与安全性」，拉到下方点「仍要打开」。"
