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
# 推送鉴权：优先用 ${TAP_TOKEN}（CI 里配的 PAT，走 https）；没有则回落到本机 SSH。
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
  echo "== tap 已是 ${VER}，无需提交 =="
  exit 0
elif [ "$PATCH_RC" != "0" ]; then
  echo "改写 cask 失败" >&2; exit 1
fi

# 4) 提交并推送（本机偶发 git 锁竞态，清锁重试）
git -c user.name="lefu release bot" -c user.email="9445146+boxter007@users.noreply.github.com" \
    add "$CASK_PATH"

# ⚠️ 提交必须显式判定成败。
#    早期写法是 `git commit ... && break`，重试 10 次后若仍失败会**静默落下**：
#    紧接着的 `git push` 在「没有新提交」时会正常返回 0（无内容可推），
#    于是脚本打印「已升级到 X」、CI 记为 success，而 tap 一个字都没变。
#    这类「假成功」正是 tap 落后一个版本却无人察觉的原因。
committed=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  rm -f .git/index.lock 2>/dev/null || true
  if git -c user.name="lefu release bot" \
         -c user.email="9445146+boxter007@users.noreply.github.com" \
         commit -q -m "cask: lefu ${VER}"; then
    committed=1; break
  fi
  sleep 0.3
done
if [ "$committed" != "1" ]; then
  echo "提交失败：重试 10 次仍无法提交 cask 改动" >&2
  exit 1
fi

pushed=0
for _ in 1 2 3 4 5; do
  if git push -q origin HEAD:main 2>/dev/null; then pushed=1; break; fi
  sleep 0.5
done
if [ "$pushed" != "1" ]; then
  echo "推送失败：无法写入 $TAP_REPO" >&2
  exit 1
fi

# 5) 回读远端确认真的落库
#    不信任 push 的退出码——上面的静默 no-op 就是这么骗过 CI 的。
git fetch -q --depth 1 origin main
remote_ver="$(git show FETCH_HEAD:"$CASK_PATH" 2>/dev/null \
  | grep -oE '^[[:space:]]*version[[:space:]]+"[^"]*"' | head -1 \
  | sed 's/.*"\(.*\)".*/\1/')"
if [ "$remote_ver" != "$VER" ]; then
  echo "校验失败：远端 cask 版本为「${remote_ver}」，期望「${VER}」" >&2
  echo "可能原因：推送未真正生效，或 tap 有分支保护。" >&2
  exit 1
fi

echo "== 完成：$TAP_REPO 已升级到 ${VER}（已回读远端确认）=="
echo "   用户侧：brew update && brew upgrade --cask lefu"
