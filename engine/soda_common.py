#!/usr/bin/env python3
# soda_common.py — 汽水内录 v2 公共库: ffmpeg 封装 / 音频清理 / 歌词 / 标签 / 目录
# v2 全链路模块 (soda_record_auto / soda_nowplaying / soda_split_v2) 共用
import os, re, subprocess, threading
from datetime import datetime
import requests

FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
UA = {"User-Agent": "soda2mp3/2.0 (personal use)"}
PRINT_LOCK = threading.Lock()

def log(i, msg):
    """线程安全日志: [歌曲序号] 消息"""
    with PRINT_LOCK:
        print(f"[{i:>2}] {msg}", flush=True)

def ff(*args):
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", *args], check=True)

def ff_out(*args):
    return subprocess.run([FFMPEG, "-hide_banner", *args], capture_output=True, text=True).stderr

def probe_duration(path):
    """精确时长: ffprobe (ffmpeg 进度输出的 time= 对长文件不可靠)"""
    r = subprocess.run([FFPROBE, "-v", "error", "-show_entries", "format=duration",
                        "-of", "csv=p=0", path], capture_output=True, text=True)
    try:
        return float(r.stdout.strip())
    except (ValueError, TypeError):
        return 0.0

def session_dir(base="~/Music/SodaMP3", date=None, create=True):
    """会话目录: base/YYYY-MM-DD (默认今天; date 可传 'YYYY-MM-DD' 或 datetime)"""
    ds = date if isinstance(date, str) else (date or datetime.now()).strftime("%Y-%m-%d")
    d = os.path.join(os.path.expanduser(base), ds)
    if create:
        os.makedirs(d, exist_ok=True)
    return d

def latest_session_dir(base="~/Music/SodaMP3"):
    """最近的会话目录: 无日期目录则退化为今天"""
    root = os.path.expanduser(base)
    dates = sorted(e for e in os.listdir(root)
                   if re.match(r"^\d{4}-\d{2}-\d{2}$", e)
                   and os.path.isdir(os.path.join(root, e)))
    return os.path.join(root, dates[-1]) if dates else session_dir(base)

def clean_segment(src, out_wav, dur):
    """去首尾静音(留0.3s垫) + 0.25s淡入淡出"""
    chain = ("silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.3,"
             "areverse,"
             "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.3,"
             "areverse,")
    fade_out_start = max(dur - 0.25, 0)
    ff("-y", "-i", src, "-af", f"{chain}afade=t=in:d=0.25,afade=t=out:st={fade_out_start:.2f}:d=0.25",
       "-ar", "48000", "-ac", "2", out_wav)

def lyrics_lrclib(title, artist):
    """LRCLIB 歌词: 先按歌名+歌手, 失败退化仅按歌名(翻唱版本歌词归属于原唱)"""
    for params in ({"track_name": title, "artist_name": artist},
                   {"track_name": title} if artist else {}):
        if not params:
            continue
        try:
            r = requests.get("https://lrclib.net/api/search",
                             params=params, headers=UA, timeout=15)
            items = r.json() if r.ok else []
            if items:
                return items[0].get("syncedLyrics") or items[0].get("plainLyrics") or ""
        except Exception as e:
            log("?", f"[LRCLIB异常] {e}")
    return ""

def lyrics_netease(title, artist):
    """网易云歌词兜底"""
    for q in (f"{title} {artist}".strip(), title):
        try:
            r = requests.get("https://music.163.com/api/search/get",
                             params={"s": q, "type": 1, "limit": 3}, headers=UA, timeout=15)
            songs = (r.json().get("result") or {}).get("songs") or []
            if not songs:
                continue
            sid = songs[0]["id"]
            r2 = requests.get("https://music.163.com/api/song/lyric",
                              params={"id": sid, "lv": 1, "tv": -1}, headers=UA, timeout=15)
            lyr = (r2.json().get("lrc") or {}).get("lyric", "")
            lyr = re.sub(r"\[.*?metadata.*?\]", "", lyr).strip()
            if lyr and "纯音乐" not in lyr[:50]:
                return lyr
        except Exception as e:
            log("?", f"[网易云异常] {e}")
    return ""

def write_tags(mp3, meta, lyrics, cover=None):
    """写 ID3 标签: 标题/歌手/专辑/内嵌歌词(USLT)/封面(APIC)"""
    from mutagen.id3 import ID3, USLT, APIC, TIT2, TPE1, TALB
    from mutagen.mp3 import MP3
    audio = MP3(mp3, ID3=ID3)
    audio["TIT2"] = TIT2(encoding=3, text=meta["title"])
    audio["TPE1"] = TPE1(encoding=3, text=meta["artist"])
    if meta.get("album"):
        audio["TALB"] = TALB(encoding=3, text=meta["album"])
    if lyrics:
        audio.tags.add(USLT(encoding=3, lang="chi", desc="lyrics", text=lyrics))
    if cover and os.path.exists(cover):
        mime = "image/png" if open(cover, "rb").read(4) == b"\x89PNG" else "image/jpeg"
        with open(cover, "rb") as f:
            audio.tags.add(APIC(encoding=3, mime=mime, type=3, desc="cover", data=f.read()))
    audio.save()
