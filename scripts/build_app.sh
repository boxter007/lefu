#!/bin/bash
# build_app.sh — 编译乐府并组装成 乐府.app
# 产物: build/.dist/乐府.app (可直接拖进 /Applications)
#
# 为什么放在隐藏目录 build/.dist/ 下：
#   Spotlight 会索引普通目录里的 .app 包，于是用户在聚焦/访达里搜「乐府」会同时
#   出现「应用程序里的乐府」和「build 里的乐府」两份。隐藏目录（以点开头）不会被
#   Spotlight 索引，故构建产物统一放进 build/.dist/。
#   实测：.metadata_never_index 标记与 com.apple.metadata:kMDItemSupportFileType
#   xattr 对本机子目录均无效，只有隐藏目录可靠。
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="build/.dist/乐府.app"

if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "== 1. swift release 编译（universal：arm64 + x86_64，两次单架构 + lipo 合并）=="
  swift build -c release --arch arm64
  swift build -c release --arch x86_64
  mkdir -p .build/apple/Products/Release
  lipo -create .build/arm64-apple-macosx/release/乐府 \
               .build/x86_64-apple-macosx/release/乐府 \
               -output .build/apple/Products/Release/乐府
else
  echo "== 1. swift release 编译 =="
  swift build -c release
fi

echo "== 2. 组装 .app 结构 =="
# 清掉历史遗留的可见产物（旧版本在 build/ 下直接生成，会被 Spotlight 索引成第二份 App）
/bin/rm -rf "$ROOT/build/乐府.app" "$ROOT/build/Shige.app" 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj" "$APP/Contents/Resources/en.lproj"
BIN=".build/release/乐府"
[ "${UNIVERSAL:-0}" = "1" ] && BIN=".build/apple/Products/Release/乐府"
[ -f "$BIN" ] || BIN=".build/release/Lefu"   # 兼容旧 target 名的本地缓存
cp "$BIN" "$APP/Contents/MacOS/乐府"

# App 图标
ICON="design/AppIcon.icns"
if [ -f "$ICON" ]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
  echo "   已内置 AppIcon.icns"
else
  echo "   警告：未找到 design/AppIcon.icns"
fi

# 内置 LAME（随 app 分发，用户机器无需 Homebrew）
LAME="/opt/homebrew/opt/lame/lib/libmp3lame.0.dylib"
if [ -f "$LAME" ]; then
  cp "$LAME" "$APP/Contents/Frameworks/"
  echo "   已内置 libmp3lame"
else
  echo "   警告：未找到 libmp3lame，运行时将回落 M4A"
fi

# —— 版本号管理（每次打包都必须更新版本号）——
# VERSION 文件：第 1 行 = 营销版本号（CFBundleShortVersionString），第 2 行 = 构建号（CFBundleVersion）
# 每跑一次本脚本，构建号自动 +1；要发新版就把 VERSION 第一行改掉，或打包时传 APP_VERSION=1.2.0 覆盖
VERSION_FILE="$ROOT/VERSION"
MARKETING=""
BUILD_NO=""
if [ -f "$VERSION_FILE" ]; then
  MARKETING="$(sed -n '1p' "$VERSION_FILE" | tr -d '[:space:]')"
  BUILD_NO="$(sed -n '2p' "$VERSION_FILE" | tr -d '[:space:]')"
fi
[ -n "$MARKETING" ] || MARKETING="1.0.0"
case "$BUILD_NO" in ''|*[!0-9]*) BUILD_NO=0 ;; esac
if [ -n "${APP_VERSION:-}" ]; then MARKETING="$APP_VERSION"; fi
BUILD_NO=$((BUILD_NO + 1))
printf '%s\n%s\n' "$MARKETING" "$BUILD_NO" > "$VERSION_FILE"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>乐府</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.jingjing.lefu</string>
    <key>CFBundleName</key><string>乐府</string>
    <key>CFBundleDisplayName</key><string>乐府</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string>
        <string>en</string>
    </array>
    <key>CFBundleAllowMixedLocalizations</key><true/>
    <key>CFBundleShortVersionString</key><string>${MARKETING}</string>
    <key>CFBundleVersion</key><string>${BUILD_NO}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSMicrophoneUsageDescription</key><string>乐府需要采集系统音频（经 BlackHole 虚拟声卡）以收录正在播放的歌曲</string>
</dict>
</plist>
PLIST

echo "== 3. 签名（显式签嵌套代码，不用已废弃的 --deep）=="
# --deep 已被 Apple 标记为不应使用：它把签名选项不加区分地套到嵌套代码上。
# 正确做法是先签 Frameworks 里的 dylib，再签主 bundle。
#
# 这里刻意不加 --options runtime（hardened runtime）：
#   实测 ad-hoc 签名没有 Team ID，一旦启用 hardened runtime，library validation 会拒绝
#   dlopen 内置的 libmp3lame.0.dylib，报 "mapping process and mapped file ... have
#   different Team IDs"，MP3 编码会静默失效（回落 M4A）。
#   等 issue #2 接入真实 Developer ID 证书后，再连同 --options runtime 一起打开并公证。
FW="$APP/Contents/Frameworks"
for lib in "$FW"/*.dylib; do
  [ -e "$lib" ] || continue
  codesign --force -s - "$lib" 2>/dev/null || echo "   警告：嵌套库签名失败 $(basename "$lib")"
done
codesign --force -s - "$APP"

# 签名必须校验通过，否则产物在别人机器上会被 Gatekeeper 拦下
if codesign --verify --strict "$APP" 2>/dev/null; then
  echo "   签名校验通过"
else
  echo "   错误：签名校验未通过，中止打包" >&2
  exit 1
fi

echo "版本 → ${MARKETING} (build ${BUILD_NO})"
echo "完成 → $APP"
echo "运行: open \"$APP\""
