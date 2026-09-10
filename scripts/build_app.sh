#!/bin/bash
# build_app.sh — 编译乐府并组装成 乐府.app
# 产物: build/乐府.app (可直接拖进 /Applications)
set -e
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="build/乐府.app"

echo "== 1. swift release 编译 =="
swift build -c release

echo "== 2. 组装 .app 结构 =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj" "$APP/Contents/Resources/en.lproj"
BIN=".build/release/乐府"
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

cat > "$APP/Contents/Info.plist" << 'PLIST'
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
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSMicrophoneUsageDescription</key><string>乐府需要采集系统音频（经 BlackHole 虚拟声卡）以收录正在播放的歌曲</string>
</dict>
</plist>
PLIST

echo "== 3. ad-hoc 签名 =="
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo "完成 → $APP"
echo "运行: open \"$APP\""
