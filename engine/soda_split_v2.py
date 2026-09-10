#!/usr/bin/env python3
# soda_split_v2.py — v2 切歌: 按正在播放时间轴切分, 元信息来自汽水, 歌词+封面
# 用法: python3 soda_split_v2.py <录音wav> <timeline.jsonl> [--min-len N] [--workers N]
# 架构 (两阶段):
#   阶段1 单线程: 按时间轴逐段 纯静音检查 → 切段 → 去首尾静音+淡入淡出  (本地磁盘IO)
#   阶段2 线程池: 每歌一个线程 抓歌词 → 编码320k → 写标签/封面 → 出 .lrc  (网络IO+编码)
# 元信息: 歌名/歌手/专辑 直接用时间轴(汽水官方数据, 无需 Shazam)
# 封面:  录制时订阅器已存 Now Playing 自带封面 → 按事件号取本地文件, 零联网
# 歌词:  LRCLIB → 网易云 (唯一联网项)
# 对齐:  优先 <wav>.epoch (录制器真实开录时刻), 无则退回 WAV 文件名时间戳
# 输出:  WAV 所在会话日期目录; 报告写 recordings/<wav名>_时间轴报告.txt
import json, os, re, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from soda_common import (ff, ff_out, probe_duration, clean_segment,
                         lyrics_lrclib, lyrics_netease, write_tags, log)
from soda_lyrics_local import local_lyrics

def parse_args(argv):
    wav, tl = argv[0], argv[1]
    min_len, workers, offline = 60, 6, False
    for i, a in enumerate(argv):
        if a == "--min-len":
            min_len = int(argv[i + 1])
        elif a == "--workers":
            workers = int(argv[i + 1])
        elif a == "--offline":
            offline = True
    return wav, tl, min_len, workers, offline

def phase1_cut(i, s, e, wav, tmp):
    """阶段1(串行): 静音检查 + 切段 + 清理。返回 ("ok", seg_wav) / ("silent", None) / ("short", None)"""
    dur = e - s
    t = time.time()
    vol = ff_out("-ss", f"{s:.1f}", "-t", f"{dur:.1f}", "-i", wav,
                 "-af", "volumedetect", "-f", "null", "-")
    mv = re.search(r"max_volume: (-?[\d.]+|-inf) dB", vol)
    peak = float(mv.group(1)) if mv and mv.group(1) != "-inf" else -120.0
    if peak < -50:
        log(i, f"纯静音段(峰值{peak:.1f}dB), 跳过 (检查耗时 {time.time()-t:.1f}s)")
        return ("silent", None)
    raw = os.path.join(tmp, f"raw{i}.wav")
    seg = os.path.join(tmp, f"seg{i}.wav")
    t2 = time.time()
    ff("-y", "-ss", f"{s:.3f}", "-t", f"{dur:.3f}", "-i", wav, "-ar", "48000", "-ac", "2", raw)
    clean_segment(raw, seg, dur)
    os.remove(raw)
    log(i, f"切段完成 {dur:.0f}s 音频 (峰值{peak:.1f}dB, 共耗时 {time.time()-t:.1f}s)")
    return ("ok", seg)

def phase2_post(i, s, e, seg_wav, ev, tmp, outdir):
    """阶段2(并发, 每歌一个线程): 歌词 → 编码 → 封面/标签 → lrc"""
    t_start = time.time()
    title = ev.get("title") or f"轨道{i:02d}"
    artist = ev.get("artist") or "未知歌手"
    album = ev.get("album", "")
    try:
        # 歌词: 本地缓存(汽水KRC, 零联网) → (--offline 到此为止) → LRCLIB → 网易云
        t = time.time()
        lyrics, src = local_lyrics(title, artist), "本地缓存"
        if not lyrics and not OFFLINE:
            lyrics, src = lyrics_lrclib(title, artist), "LRCLIB"
        if not lyrics and not OFFLINE:
            lyrics, src = lyrics_netease(title, artist), "网易云"
        log(i, f"歌词: {'✓ ' + str(len(lyrics)) + '字(' + src + ')' if lyrics else '未找到'} (耗时 {time.time()-t:.1f}s)")
        # 本地封面 (录制时订阅器已存)
        cover = None
        art_name = ev.get("artwork")
        if art_name and ARTWORK_DIR:
            p = os.path.join(ARTWORK_DIR, art_name)
            cover = p if os.path.exists(p) else None
        log(i, f"封面: {'✓ ' + os.path.basename(cover) if cover else '无'}")
        # 编码 320k
        t = time.time()
        safe = re.sub(r'[/:*?"<>|]', "_", f"{artist} - {title}".strip(" -"))
        mp3 = os.path.join(outdir, safe + ".mp3")
        k = 2
        while os.path.exists(mp3):
            mp3 = os.path.join(outdir, f"{safe} ({k}).mp3"); k += 1
        ff("-y", "-i", seg_wav, "-codec:a", "libmp3lame", "-b:a", "320k", mp3)
        log(i, f"编码 320k 完成 (耗时 {time.time()-t:.1f}s)")
        # 标签 + lrc
        meta = {"title": title, "artist": artist, "album": album}
        write_tags(mp3, meta, lyrics, cover)
        if lyrics:
            open(os.path.join(outdir, os.path.splitext(os.path.basename(mp3))[0] + ".lrc"),
                 "w", encoding="utf-8").write(lyrics)
        log(i, f"完成 → {os.path.basename(mp3)} (本歌总耗时 {time.time()-t_start:.1f}s)")
        line = (f"✓ {s:>7.0f}-{e:<7.0f} {artist} - {title}"
                + (f"  [歌词{len(lyrics)}字]" if lyrics else "")
                + ("" if cover else "  [无封面]"))
        return (i, line, mp3)
    except Exception as ex:
        log(i, f"处理失败: {ex}")
        return (i, f"! {s:>7.0f}-{e:<7.0f} {artist} - {title} [异常: {ex}]", None)

ARTWORK_DIR = None
OFFLINE = False

def main():
    global ARTWORK_DIR, OFFLINE
    wav, tl_path, min_len, workers, offline = parse_args(sys.argv[1:])
    if not os.path.exists(wav):
        raise SystemExit(f"录音不存在: {wav}")
    if not os.path.exists(tl_path):
        raise SystemExit(f"时间轴不存在: {tl_path}")
    outdir = os.path.dirname(os.path.abspath(wav)).replace("/recordings", "")
    # 开录基准 epoch: 优先 <wav>.epoch (真实开录时刻), 退回文件名时间戳
    ep_file = wav + ".epoch"
    if os.path.exists(ep_file):
        rec_epoch = float(open(ep_file).read().strip())
        print(f"开录基准: {rec_epoch:.1f} (来自 {os.path.basename(ep_file)}, 精确)")
    else:
        m = re.search(r"session_(\d{8})_(\d{6})\.wav$", os.path.basename(wav))
        if not m:
            raise SystemExit("WAV 文件名须为 session_YYYYmmdd_HHMMSS.wav (且无 .epoch 文件)")
        rec_epoch = datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S").timestamp()
        print(f"开录基准: {rec_epoch:.1f} (来自文件名, 有约1-3s启动误差)")
    total = probe_duration(wav)
    print(f"录音总长 {total/60:.1f} 分钟")

    events = [json.loads(l) for l in open(tl_path, encoding="utf-8") if l.strip()]
    if not events:
        raise SystemExit("时间轴为空(录制期间没读到播放信息?)")
    # 合并虚假换歌事件: 相邻同歌名+同歌手, 间隔不超过上一条的时长
    # (播放器上报的时长小数位抖动会触发重复上报, replay 事件除外)
    merged = []
    for ev in events:
        prev = merged[-1] if merged else None
        if (prev and not ev.get("replay")
                and ev.get("title") == prev.get("title")
                and ev.get("artist") == prev.get("artist")
                and prev.get("duration")
                and (ev["epoch"] - prev["epoch"]) <= prev["duration"] + 5):
            continue
        merged.append(ev)
    if len(merged) < len(events):
        print(f"已合并 {len(events) - len(merged)} 条同歌重复上报事件")
    events = merged
    segs = []
    for i, ev in enumerate(events):
        s = ev["epoch"] - rec_epoch
        e = events[i + 1]["epoch"] - rec_epoch if i + 1 < len(events) else total
        s, e = max(s, 0.0), min(e, total)
        if e - s >= 1:
            segs.append((s, e, ev))
    print(f"时间轴共 {len(events)} 首歌, 其中 {len(segs)} 段有效"
          + (", 离线模式(歌词仅本地缓存)" if offline else ""))
    OFFLINE = offline
    ARTWORK_DIR = tl_path + ".artworks"

    tmp = os.path.join(outdir, ".tmp_split"); os.makedirs(tmp, exist_ok=True)
    report, made = [], []

    # ---- 阶段1 (单线程): 找段+切段 ----
    t1 = time.time()
    to_post, results = [], []
    for i, (s, e, ev) in enumerate(segs, 1):
        dur = e - s
        artist, title = ev.get("artist") or "未知歌手", ev.get("title") or f"轨道{i:02d}"
        print(f"\n== [{i}] {s:.0f}s-{e:.0f}s ({dur/60:.1f}分钟) {artist} - {title}", flush=True)
        if dur < min_len:
            print(f"  短于{min_len}s, 跳过", flush=True)
            report.append(f"- {s:>7.0f}-{e:<7.0f} {artist} - {title} [过短, 已跳过]")
            continue
        status, seg_wav = phase1_cut(i, s, e, wav, tmp)
        if status == "silent":
            report.append(f"- {s:>7.0f}-{e:<7.0f} {artist} - {title} [纯静音, 已跳过]")
        else:
            to_post.append((i, s, e, seg_wav, ev))
    print(f"\n阶段1完成: 切出 {len(to_post)} 段, 耗时 {time.time()-t1:.0f}s, 启动 {workers} 线程后处理", flush=True)

    # ---- 阶段2 (多线程): 每歌一个 pipeline ----
    t2 = time.time()
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(phase2_post, i, s, e, seg_wav, ev, tmp, outdir)
                for i, s, e, seg_wav, ev in to_post]
        for f in as_completed(futs):
            results.append(f.result())
    results.sort(key=lambda r: r[0])
    report += [r[1] for r in results]
    made = [r[2] for r in results if r[2]]

    os.system(f"rm -rf {tmp!r}")
    rpt = os.path.join(outdir, "recordings",
                       os.path.splitext(os.path.basename(wav))[0] + "_时间轴报告.txt")
    os.makedirs(os.path.dirname(rpt), exist_ok=True)
    open(rpt, "w", encoding="utf-8").write("\n".join(report) + "\n")
    print("\n---- 会话报告 ----")
    print("\n".join(report))
    print(f"\n成品 {len(made)} 个 → {outdir}  (切段 {time.time()-t1:.0f}s + 后处理 {time.time()-t2:.0f}s)")

if __name__ == "__main__":
    main()
