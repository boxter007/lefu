#!/usr/bin/env python3
# soda_nowplaying.py — 订阅 macOS 正在播放(Now Playing)信息, 记录换歌时间轴
# 用法: python3 soda_nowplaying.py <输出jsonl> [轮询间隔秒=1] [过滤bundle=com.soda.music] [录制起始epoch]
# 原理: 轮询 nowplaying-cli get-raw, 歌名/歌手/时长变化 或 进度回跳(同一首歌连播)即换歌事件,
#       追加一行 JSON: {epoch, 时间, 相对录制偏移秒, 歌名, 歌手, 专辑, 时长}
#       时间轴与内录 WAV 对齐(offset 自录制起始算) → 精确切歌 + 直接命名
import base64, json, os, subprocess, sys, time
from datetime import datetime

CLI = "/opt/homebrew/bin/nowplaying-cli"
EVENT_N = 0  # 事件序号, 用于封面文件命名

def now_playing():
    try:
        r = subprocess.run([CLI, "get-raw"], capture_output=True, text=True, timeout=5)
        return json.loads(r.stdout) if r.stdout.strip() else {}
    except Exception:
        return {}

def save_artwork(info, art_dir, offset):
    """Now Playing 自带封面字节, 零联网存盘。返回封面路径或 None"""
    global EVENT_N
    data = info.get("kMRMediaRemoteNowPlayingInfoArtworkData")
    if not data:
        return None
    try:
        raw = base64.b64decode(data) if isinstance(data, str) else data
        if not raw or len(raw) < 100:
            return None
        ext = "png" if raw[:4] == b"\x89PNG" else "jpg"
        os.makedirs(art_dir, exist_ok=True)
        p = os.path.join(art_dir, f"ev{EVENT_N:03d}_{offset:.0f}s.{ext}")
        open(p, "wb").write(raw)
        return p
    except Exception:
        return None

def main():
    out = os.path.expanduser(sys.argv[1])
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    only_bundle = sys.argv[3] if len(sys.argv) > 3 else "com.soda.music"
    start_epoch = float(sys.argv[4]) if len(sys.argv) > 4 else None
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    t0 = time.time()
    base = start_epoch if start_epoch else t0   # offset 基准: 录制起始时刻
    last_key, last_elapsed = None, None
    print(f"订阅中 → {out}  (每{interval}s轮询, bundle={only_bundle})", flush=True)
    while True:
        now = time.time()
        info = now_playing()
        bundle = info.get("kMRMediaRemoteNowPlayingInfoClientBundleIdentifier", "")
        if only_bundle and bundle != only_bundle:
            time.sleep(interval)
            continue
        # 换歌判定只看 歌名+歌手 (时长/进度的小数位会抖动, 不能作为判定依据)
        key = (info.get("kMRMediaRemoteNowPlayingInfoTitle"),
               info.get("kMRMediaRemoteNowPlayingInfoArtist"))
        duration = info.get("kMRMediaRemoteNowPlayingInfoDuration")
        elapsed = info.get("kMRMediaRemoteNowPlayingInfoElapsedTime") or 0
        # 重播判定: 同一首歌进度回跳>5s(连播/重播)
        replay = (last_key == key and last_elapsed is not None
                  and elapsed < last_elapsed - 5)
        if key[0] and (key != last_key or replay):
            global EVENT_N
            ev = {
                "epoch": round(now, 1),
                "time": datetime.now().isoformat(timespec="seconds"),
                "offset": round(now - base, 1),
                "title": key[0],
                "artist": key[1] or "",
                "album": info.get("kMRMediaRemoteNowPlayingInfoAlbum", ""),
                "duration": duration,
                "replay": replay,
            }
            art = save_artwork(info, out + ".artworks", ev["offset"])
            ev["artwork"] = os.path.basename(art) if art else ""
            EVENT_N += 1
            with open(out, "a", encoding="utf-8") as f:
                f.write(json.dumps(ev, ensure_ascii=False) + "\n")
            tag = " [重播]" if replay else ""
            print(f"[{ev['offset']:>8.1f}s] {ev['artist']} - {ev['title']}  ({ev['duration']}s){tag}"
                  + ("  封面✓" if art else ""), flush=True)
            last_key = key
        if key[0]:
            last_elapsed = elapsed
        time.sleep(interval)

if __name__ == "__main__":
    main()
