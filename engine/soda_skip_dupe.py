#!/usr/bin/env python3
# soda_skip_dupe.py — 已录歌曲自动跳过器
# 用法: python3 soda_skip_dupe.py [额外扫描目录...]
# 逻辑: 每2秒读当前播放(仅汽水), 若 "歌手 - 歌名" 已存在 mp3 (~/Music/SodaMP3 全目录递归),
#       立即发送 next 并等歌名变化, 防止连跳。重复文件以 (2)(3) 结尾的也计入。
import json, os, re, subprocess, sys, time
from datetime import datetime

CLI = "/opt/homebrew/bin/nowplaying-cli"
DEFAULT_ROOTS = [os.path.expanduser("~/Music/SodaMP3")]
CHECK_INTERVAL = 2.0
RESCAN_INTERVAL = 60.0

def normalize(s):
    """归一化: 小写、去重名序号(2)、去所有标点空格, 用于文件名↔播放信息匹配"""
    s = s.lower().strip()
    s = re.sub(r"\(\d+\)$", "", s)  # 尾部 (2) 重名序号
    s = re.sub(r"[\s\-_·・,，。.()（）\[\]【】'\"“”‘’!！?？/\\:：;；&]", "", s)
    return s

def build_index(roots):
    idx = set()
    for root in roots:
        for dp, _, fns in os.walk(root):
            for fn in fns:
                if fn.lower().endswith(".mp3"):
                    idx.add(normalize(os.path.splitext(fn)[0]))
    return idx

def now_playing():
    try:
        r = subprocess.run([CLI, "get-raw"], capture_output=True, text=True, timeout=5)
        if not r.stdout.strip():
            return None
        d = json.loads(r.stdout)
        if d.get("kMRMediaRemoteNowPlayingInfoClientBundleIdentifier") != "com.soda.music":
            return None
        title = d.get("kMRMediaRemoteNowPlayingInfoTitle") or ""
        artist = d.get("kMRMediaRemoteNowPlayingInfoArtist") or ""
        if not title:
            return None
        return title, artist
    except Exception:
        return None

def log(msg):
    print(f"[{datetime.now():%H:%M:%S}] {msg}", flush=True)

def main():
    roots = DEFAULT_ROOTS + [os.path.expanduser(a) for a in sys.argv[1:]]
    recorded = build_index(roots)
    last_rescan = time.time()
    last_key, cooldown_until = None, 0
    log(f"已录跳过器启动: 监控 {len(recorded)} 首已录 mp3, 扫描目录 {roots}")
    while True:
        now = time.time()
        if now - last_rescan > RESCAN_INTERVAL:
            recorded = build_index(roots)
            last_rescan = now
        info = now_playing()
        if info:
            title, artist = info
            key = (title, artist)
            if key != last_key:          # 换歌了才判定
                match = normalize(f"{artist} - {title}") in recorded \
                        or normalize(title) in recorded
                if match and now >= cooldown_until:
                    log(f"已录过 → 跳过: {artist} - {title}")
                    subprocess.run([CLI, "next"], timeout=5)
                    cooldown_until = time.time() + 8  # 等切歌生效, 防连跳
                elif match:
                    log(f"已录过(冷却中, 不重复跳): {artist} - {title}")
            last_key = key
        time.sleep(CHECK_INTERVAL)

if __name__ == "__main__":
    main()
