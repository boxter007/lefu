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

# —— 最低支持版本：macOS 11 (Big Sur) ——
# Package.swift 的 platforms 只是 SwiftPM 声明，真正写进 Mach-O 的是这里的
# MACOSX_DEPLOYMENT_TARGET。两者必须一致，否则会出现「装得上但起不来」——
# 例如 SDK 是 macOS 26 时默认 minos 可能被推到很高，旧系统直接 dyld 报错。
# export 后 swift build / clang 都会继承，无需改 Package.swift 之外的地方。
export MACOSX_DEPLOYMENT_TARGET=12.0
# 让链接器只警告不报错地接受对更高版本符号的引用（11 以下没有的 API 由 #available 兜住）
export SWIFT_VERSION=5

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
#
# ⚠️ 关键：不能直接拷构建机的 Homebrew libmp3lame。
#    Homebrew 的 dylib 会带上构建机 SDK 的 minos（实测 macOS 26 上编译出来的是
#    minos 26.0），拷进包里后在低于该版本的机器上 dlopen 必然失败；
#    而 LameEncoder 的失败路径是「静默回落 M4A」——用户拿到一堆 M4A，
#    界面不报错，README 却承诺 MP3 320k。这是最难排查的一类问题。
#
#    正确做法：用 LAME 官方源码、以固定的 -mmacosx-version-min 自己编译，
#    让 dylib 的目标版本由我们决定，而不是由构建机决定。
LAME_DIR="${LAME_DIR:-$ROOT/build/lame}"
# 注意路径里的 /lib：--prefix 把库装到 $prefix/lib 下，
# 早先写成 $LAME_DIR/libmp3lame.0.dylib 是错的——源码编译明明成功，
# 脚本却找不到产物，于是误回落 Homebrew 的高 minos dylib。
LAME_DYLIB="$LAME_DIR/lib/libmp3lame.0.dylib"
LAME_MIN="${LAME_MIN:-12.0}"          # dylib 的最低系统版本，与 app 保持一致

build_lame_from_source() {
  local ver="3.100"
  local tarball="$ROOT/build/lame-$ver.tar.gz"
  mkdir -p "$ROOT/build"
  if [ ! -f "$tarball" ]; then
    echo "   下载 LAME $ver 源码…"
    curl -fsSL -o "$tarball" \
      "https://downloads.sourceforge.net/project/lame/lame/$ver/lame-$ver.tar.gz" \
      || { echo "   错误：LAME 源码下载失败" >&2; return 1; }
  fi
  local src="$ROOT/build/lame-$ver"
  [ -d "$src" ] || tar xzf "$tarball" -C "$ROOT/build"

  # LAME 3.100 在 macOS arm64 上的已知链接错误：
  #   Undefined symbols for architecture arm64: "_lame_init_old"
  # 原因是导出列表 include/libmp3lame.sym 里列了这个已废弃符号，而它在 arm64
  # 构建里被编译成 static（见 lame.c 的 DEPRECATED_OR_OBSOLETE_CODE_REMOVED）。
  # 修法：从导出列表里删掉该符号——它是 obsolete API，乐府只用 lame_init/encode。
  local sym="$src/include/libmp3lame.sym"
  if [ -f "$sym" ] && grep -q '^lame_init_old$' "$sym"; then
    grep -v '^lame_init_old$' "$sym" > "$sym.tmp" && mv "$sym.tmp" "$sym"
    echo "   已从导出列表移除 obsolete 符号 lame_init_old（arm64 链接所需）"
  fi

  # 编译单个架构的辅助函数。UNIVERSAL=1 时对 arm64 与 x86_64 各编一次再 lipo 合并，
  # 否则 Intel 机器上 dlopen 会失败、静默回落 M4A（对应 issue #13）。
  _build_one_arch() {
    local arch="$1" outdir="$2"
    # x86_64 需要显式指定 host，否则 configure 会按 Apple Silicon 探测出 arm64
    local hostflag=""
    [ "$arch" = "x86_64" ] && hostflag="--host=x86_64-apple-darwin"
    make distclean >/dev/null 2>&1 || true
    ( cd "$src" && \
      CFLAGS="-O2 -mmacosx-version-min=$LAME_MIN -arch $arch" \
      LDFLAGS="-mmacosx-version-min=$LAME_MIN -arch $arch" \
      ./configure --prefix="$outdir" $hostflag \
        --enable-shared --disable-static --disable-frontend >/dev/null ) || return 1
    # 每次 configure 都会重新展开 libmp3lame.sym，需再删一次 obsolete 符号
    [ -f "$sym" ] && grep -q '^lame_init_old$' "$sym" && \
      grep -v '^lame_init_old$' "$sym" > "$sym.tmp" && mv "$sym.tmp" "$sym"
    ( cd "$src" && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null ) || return 1
    return 0
  }

  if [ "${UNIVERSAL:-0}" = "1" ]; then
    echo "   编译 LAME：arm64 + x86_64（universal）…"
    local a_dir="$ROOT/build/lame-arm64" x_dir="$ROOT/build/lame-x86_64"
    /bin/rm -rf "$a_dir" "$x_dir"
    _build_one_arch arm64  "$a_dir" || { echo "   错误：LAME arm64 编译失败" >&2; return 1; }
    _build_one_arch x86_64 "$x_dir" || { echo "   错误：LAME x86_64 编译失败" >&2; return 1; }
    mkdir -p "$LAME_DIR/lib"
    lipo -create "$a_dir/lib/libmp3lame.0.dylib" "$x_dir/lib/libmp3lame.0.dylib" \
      -output "$LAME_DIR/lib/libmp3lame.0.dylib" \
      || { echo "   错误：lipo 合并 libmp3lame 失败" >&2; return 1; }
  else
    echo "   编译 LAME：$(uname -m)…"
    make distclean >/dev/null 2>&1 || true
    ( cd "$src" && \
      CFLAGS="-O2 -mmacosx-version-min=$LAME_MIN" \
      LDFLAGS="-mmacosx-version-min=$LAME_MIN" \
      ./configure --prefix="$LAME_DIR" --enable-shared --disable-static --disable-frontend \
        >/dev/null && \
      make -j"$(sysctl -n hw.ncpu)" >/dev/null && \
      make install >/dev/null ) \
      || { echo "   错误：LAME 编译失败" >&2; return 1; }
  fi
  return 0
}

# 优先用已编译好的；没有就现场编；再不行才回落 Homebrew（并给出明确警告）
if [ ! -f "$LAME_DYLIB" ]; then
  echo "   源码编译 libmp3lame（mmacosx-version-min=$LAME_MIN）…"
  build_lame_from_source || true
fi

if [ ! -f "$LAME_DYLIB" ]; then
  HB_LAME="/opt/homebrew/opt/lame/lib/libmp3lame.0.dylib"
  [ -f "$HB_LAME" ] || HB_LAME="/usr/local/opt/lame/lib/libmp3lame.0.dylib"
  if [ -f "$HB_LAME" ]; then
    echo "   ⚠️  回落 Homebrew LAME：$HB_LAME"
    echo "   ⚠️  该 dylib 可能带高 minos，旧系统会静默回落 M4A（见下方校验）"
    LAME_DYLIB="$HB_LAME"
  fi
fi

if [ -f "$LAME_DYLIB" ]; then
  cp "$LAME_DYLIB" "$APP/Contents/Frameworks/"
  # 修掉 install_name，保证运行时从包内加载而不是去 /opt/homebrew 找
  install_name_tool -id "@rpath/libmp3lame.0.dylib" \
    "$APP/Contents/Frameworks/libmp3lame.0.dylib" 2>/dev/null || true
  echo "   已内置 libmp3lame"

  # —— 架构校验：universal 构建里 dylib 必须同样是 fat ——
  # 防的是 issue #13 的复发：主程序是 arm64+x86_64，内置 dylib 只有 arm64，
  # Intel 机器上 dlopen 失败 → 静默回落 M4A。
  if [ "${UNIVERSAL:-0}" = "1" ]; then
    LAME_ARCHS="$(lipo -archs "$APP/Contents/Frameworks/libmp3lame.0.dylib" 2>/dev/null || echo '?')"
    case "$LAME_ARCHS" in
      *arm64*x86_64*|*x86_64*arm64*)
        echo "   libmp3lame 架构=$LAME_ARCHS ✓（universal）" ;;
      *)
        echo "   错误：libmp3lame 架构=$LAME_ARCHS，但这是 universal 构建" >&2
        echo "   Intel 机器上将无法编码 MP3（会静默回落 M4A）。中止打包。" >&2
        exit 1 ;;
    esac
  fi

  # —— 产物校验：dylib 的 minos 必须 <= LAME_MIN ——
  # 这条校验是本次改动的核心价值：把「静默降级」变成「构建期硬失败」。
  #
  # 判定用「排序后最大的那个是不是 LAME_MINOS」表达 LAME_MINOS > LAME_MIN。
  # 早期写法 `sort -V | head -1 != LAME_MIN` 是**反的**：它只会在 minos 低于
  # 目标时报错，而 minos 高于目标（真正危险的情形，如 26.0 vs 12.0）反而静默通过。
  # 务必保持「取最大者」的写法。
  LAME_MINOS="$(otool -l "$APP/Contents/Frameworks/libmp3lame.0.dylib" 2>/dev/null \
    | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f&&/minos|version/{print $2; exit}')"
  if [ -n "$LAME_MINOS" ]; then
    NEWER="$(printf '%s\n%s\n' "$LAME_MIN" "$LAME_MINOS" | sort -V | tail -1)"
    if [ "$LAME_MINOS" != "$LAME_MIN" ] && [ "$NEWER" = "$LAME_MINOS" ]; then
      echo "   错误：libmp3lame 的 minos=$LAME_MINOS 高于目标 $LAME_MIN" >&2
      echo "   这会导致旧系统上 dlopen 失败并静默回落 M4A。中止打包。" >&2
      echo "   排查：确认 LAME 由源码编译（build/lame），而非拷贝 Homebrew 的 dylib。" >&2
      exit 1
    fi
    echo "   libmp3lame minos=$LAME_MINOS ✓（目标 $LAME_MIN）"
  fi
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
    <key>LSMinimumSystemVersion</key><string>12.0</string>
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

# —— 主程序 minos 校验：确保实际部署目标 == 声明的最低版本 ——
# 防的是「Package.swift 写 .v12、SwiftPM 却按 SDK 默认值出包」这类静默不一致。
# 判定与上面的 LAME 校验同理：minos 高于目标即失败。
BIN_MINOS="$(otool -l "$APP/Contents/MacOS/乐府" 2>/dev/null \
  | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f&&/minos|version/{print $2; exit}')"
if [ -n "$BIN_MINOS" ]; then
  BIN_NEWER="$(printf '%s\n%s\n' "$MACOSX_DEPLOYMENT_TARGET" "$BIN_MINOS" | sort -V | tail -1)"
  if [ "$BIN_MINOS" != "$MACOSX_DEPLOYMENT_TARGET" ] && [ "$BIN_NEWER" = "$BIN_MINOS" ]; then
    echo "   错误：主程序 minos=$BIN_MINOS 高于目标 $MACOSX_DEPLOYMENT_TARGET，中止打包" >&2
    exit 1
  fi
  echo "   主程序 minos=$BIN_MINOS ✓（目标 $MACOSX_DEPLOYMENT_TARGET）"
else
  echo "   警告：未能读到主程序 minos，跳过校验"
fi

echo "版本 → ${MARKETING} (build ${BUILD_NO})"
echo "完成 → $APP"
echo "运行: open \"$APP\""
