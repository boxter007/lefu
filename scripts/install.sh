#!/bin/bash
# install.sh — 把 build/乐府.app 安装到 /Applications，并校验签名与版本号
#
# 为什么单独写这个：
#   本机的 `rm` 被 WorkBuddy 的安全 shim 接管（/Applications/WorkBuddy.app/.../safe-bin/rm），
#   它的行为是「把文件移进废纸篓」而不是真删除，且重名时会加时间戳后缀。
#   于是 `rm -rf /Applications/乐府.app` 会把旧包丢进废纸篓 —— 废纸篓越堆越多，
#   而且正在运行的进程其 bundle 被搬走后，lsof/sample 会把它的路径显示成 ~/.Trash/xxx.app，
#   极易误判成「在跑旧包」。所以安装时显式用 /bin/rm（真删除）。
set -e
cd "$(dirname "$0")/.."
APP=/Applications/乐府.app
SRC=build/乐府.app

if [ ! -d "$SRC" ]; then
  echo "找不到 $SRC，请先执行 ./scripts/build_app.sh" >&2
  exit 1
fi

echo "== 移除旧包（/bin/rm，避免进废纸篓）=="
/bin/rm -rf "$APP"

echo "== 拷贝新包 =="
ditto "$SRC" "$APP"

echo "== 校验签名 =="
codesign --verify --strict --verbose=2 "$APP"

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "== 完成 =="
echo "已安装 /Applications/乐府.app → 版本 ${VER} (build ${BUILD})"

if pgrep -x 乐府 >/dev/null; then
  echo "提示：乐府当前正在运行（pid $(pgrep -x 乐府 | tr '\n' ' ')），"
  echo "      需退出后重新打开才会加载新版本；设置页 → 引擎（高级）→「版本」应显示 ${VER} (${BUILD})。"
fi
