#!/bin/bash
# bump_cask.sh — 把 Homebrew tap (boxter007/homebrew-lefu) 的 cask 升到指定版本
#
# 用法：
#   bash scripts/bump_cask.sh v1.0.1                  # 从 GitHub Release 资产读 sha256
#   bash scripts/bump_cask.sh v1.0.1 --zip build/Lefu-v1.0.1.zip   # 用本地 zip 算 sha256（CI 用这条）
#   bash scripts/bump_cask.sh 1.0.1 --sha256 <hex>     # 直接给哈希
#
# 为什么要做成脚本：tap 的版本号与 sha256 靠手工同步极易漏（本仓库就漏过一次：
# cask 停在 1.0.0 而 release 已到 1.0.1）。脚本化后本地和 CI 都能一键对齐。
#
# 推送鉴权：优先用 $TAP_TOKEN（CI 里配的 PAT，走 https）；没有则回落到本机 SSH。
set -euo pipefail

TAP_REPO="boxter007/homebrew-lefu"
CASK_PATH="Casks/lefu.rb"

VER=""
SHA=""
ZIP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sha256) SHA="$2"; shift 2 ;;
    --zip)    ZIP="$2"; shift 2 ;;
    -*) echo "未知参数: $1" >&2; exit 2 ;;
    *)  VER="$1"; shift ;;
  esac
done

[ -n "$VER" ] || { echo "用法: $0 <版本或tag> [--zip 路径 | --sha256 哈希]" >&2; exit 2; }
VER="${VER#v}"                       # 去掉可能带的 v 前缀
TAG="v$VER"

# 1) 定 sha256
if [ -n "$SHA" ]; then
  :
elif [ -n "$ZIP" ]; then
  [ -f "$ZIP" ] || { echo "找不到 zip: $ZIP" >&2; exit 1; }
  SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  echo "== 由本地 zip 计算 sha256 =="
else
  echo "== 从 GitHub Release 读取 sha256 =="
  if [ -n "${TAP_TOKEN:-}" ]; then
    AUTH="Authorization: token $TAP_TOKEN"
  else
    AUTH=""
  fi
  JSON="$(curl -sS -H "$AUTH" "https://api.github.com/repos/boxter007/lefu/releases/tags/$TAG")"
  # 优先用资产自带的 digest 字段，没有就下载下来算
  SHA="$(printf '%s' "$JSON" | python3 -c '
import sys, json
d = json.load(sys.stdin)
for a in d.get("assets", []):
    if a.get("digest", "").startswith("sha256:"):
        print(a["digest"].split(":", 1)[1]); break
')"
  if [ -z "$SHA" ]; then
    echo "   资产未提供 digest，下载后计算…"
    TMP="$(mktemp -d)"
    curl -sSL -o "$TMP/Lefu-$TAG.zip" \
      "https://github.com/boxter007/lefu/releases/download/$TAG/Lefu-$TAG.zip"
    SHA="$(shasum -a 256 "$TMP/Lefu-$TAG.zip" | awk '{print $1}')"
    rm -rf "$TMP"
  fi
fi

case "$SHA" in
  [0-9a-f][0-9a-f]*) [ ${#SHA} -eq 64 ] || { echo "sha256 长度不对: $SHA" >&2; exit 1; } ;;
  *) echo "sha256 非法: $SHA" >&2; exit 1 ;;
esac
echo "   版本 $VER  sha256 $SHA"

# 2) 取 tap（有 token 走 https 以便推送，否则用本机 SSH）
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [ -n "${TAP_TOKEN:-}" ]; then
  CLONE_URL="https://x-access-token:${TAP_TOKEN}@github.com/${TAP_REPO}.git"
else
  CLONE_URL="git@github.com:${TAP_REPO}.git"
fi
git clone -q --depth 1 "$CLONE_URL" "$WORK/tap"
cd "$WORK/tap"

# 3) 改写 cask 的 version 与 sha256（幂等：值相同就不提交）
# 注意：python 以 3 表示「无变化」，用 || 捕获退出码，避免 set -e 直接中断
PATCH_RC=0
python3 - "$CASK_PATH" "$VER" "$SHA" <<'PY' || PATCH_RC=$?
import re, sys
path, ver, sha = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, encoding="utf-8").read()
new = re.sub(r'^(\s*version\s*)"[^"]*"', rf'\g<1>"{ver}"', src, count=1, flags=re.M)
new = re.sub(r'^(\s*sha256\s*)"[^"]*"', rf'\g<1>"{sha}"', new, count=1, flags=re.M)
if new == src:
    print("已是最新，无需改动"); sys.exit(3)
open(path, "w", encoding="utf-8").write(new)
print("已更新 cask")
PY
if [ "$PATCH_RC" = "3" ]; then
  echo "== tap 已是 $VER，无需提交 =="
  exit 0
elif [ "$PATCH_RC" != "0" ]; then
  echo "改写 cask 失败" >&2; exit 1
fi

# 4) 提交并推送（本机偶发 git 锁竞态，清锁重试）
git -c user.name="lefu release bot" -c user.email="9445146+boxter007@users.noreply.github.com" \
    add "$CASK_PATH"
for i in 1 2 3 4 5 6 7 8 9 10; do
  rm -f .git/index.lock 2>/dev/null || true
  git -c user.name="lefu release bot" -c user.email="9445146+boxter007@users.noreply.github.com" \
      commit -q -m "cask: lefu $VER" && break
  sleep 0.3
done

for i in 1 2 3 4 5; do
  if git push -q origin HEAD:main 2>/dev/null; then break; fi
  [ "$i" = "5" ] && { echo "推送失败" >&2; exit 1; }
  sleep 0.5
done

echo "== 完成：$TAP_REPO 已升级到 $VER =="
echo "   用户侧：brew update && brew upgrade --cask lefu"
