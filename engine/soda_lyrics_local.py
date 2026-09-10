#!/usr/bin/env python3
# soda_lyrics_local.py — 从汽水音乐本地缓存提取歌词 (零联网)
# 数据源: ~/Library/Application Support/SodaMusic/LunaCacheV2/entries.db
# 格式: MessagePack 追加日志; 每条歌词记录 = KRC逐字LRC文本 + "krck"键 + track_id + 专辑名
# KRC 行格式: [起始ms,时长ms]<词内偏移,词长>词1 <偏移,长>词2 ...
# 输出: 转成标准 LRC ([mm:ss.xx]歌词行)
import os, re
from datetime import datetime

DB_PATH = os.path.expanduser(
    "~/Library/Application Support/SodaMusic/LunaCacheV2/entries.db")

_KRCK_LINE = re.compile(rb"\[(\d{3,7}),\d{3,7}\]((?:<\d{1,6},\d{1,6},\d{1,2}>[^\n\[]*)+)")
_TRACK_ID = re.compile(rb"\xb3(\d{19})")  # msgpack fixstr19, 19位数字ID
_LRC_LINE = re.compile(rb"\[(\d{1,2}):(\d{2})\.(\d{2,3})\]([^\n\[\r]+)")

def _ms_to_lrc(ms):
    s, ms2 = divmod(int(ms), 1000)
    m, s = divmod(s, 60)
    return f"[{m:02d}:{s:02d}.{ms2 // 10:02d}]"

def _krc_to_lrc(raw):
    """KRC 逐字文本 → 标准逐行 LRC"""
    out = []
    for m in _KRCK_LINE.finditer(raw):
        start_ms = int(m.group(1))
        words = re.findall(rb"<\d{1,6},\d{1,6},\d{1,2}>([^\n<]*)", m.group(2))
        text = b"".join(words).decode("utf-8", "ignore").strip()
        if text:
            out.append(_ms_to_lrc(start_ms) + text)
    return "\n".join(out)

def _plain_lrc(raw):
    out = []
    for m in _LRC_LINE.finditer(raw):
        text = m.group(4).decode("utf-8", "ignore").strip()
        if text:
            out.append(f"[{int(m.group(1)):02d}:{m.group(2).decode()}.{m.group(3).decode()[:2]}]{text}")
    return "\n".join(out)

def _find_track_id_near(data, pos, back=200, fwd=600):
    """位置附近最近出现的 track_id"""
    seg = data[max(0, pos - back):pos + fwd]
    ids = _TRACK_ID.findall(seg)
    return ids[0].decode() if ids else None

def _parse_str_before(data, e, max_back=65536):
    """e = 字符串结束位置(\xc2 之前)。向前扫描找 msgpack str 头(\xd9/\xda/\xdb),
    其长度字段正好落在 e —— 即完整歌词字符串"""
    lo = max(0, e - max_back)
    for s in range(e - 5, lo, -1):
        b0 = data[s]
        if b0 == 0xd9:
            L = data[s + 1]; hl = 2
        elif b0 == 0xda:
            L = int.from_bytes(data[s + 1:s + 3], "big"); hl = 3
        elif b0 == 0xdb:
            L = int.from_bytes(data[s + 1:s + 5], "big"); hl = 5
        else:
            continue
        if L < 100:
            continue
        if s + hl + L == e:
            return data[s + hl:e]
    return None

def scan_db(db_path=DB_PATH):
    """扫描 db, 返回 {track_id: {"krc_lrc": ..., "line_lrc": ...}}"""
    if not os.path.exists(db_path):
        return {}
    data = open(db_path, "rb").read()
    out = {}
    # 记录特征: 歌词字符串 + \xc2(false) + \xa3krck + ... + \xb3<track_id>
    for m in re.finditer(rb"\xc2\xa3krck", data):
        raw = _parse_str_before(data, m.start())
        if not raw:
            continue
        tid_m = _TRACK_ID.search(data[m.end():m.end() + 250])
        if not tid_m:
            continue
        tid = tid_m.group(1).decode()
        entry = out.setdefault(tid, {})
        krc = _krc_to_lrc(raw)
        line = _plain_lrc(raw)
        if len(krc) > len(entry.get("krc_lrc", "")):
            entry["krc_lrc"] = krc
        if len(line) > len(entry.get("line_lrc", "")):
            entry["line_lrc"] = line
    return out

_KRC_HEAD = re.compile(rb"\[\d{3,7},\d{3,7}\]<\d{1,6},\d{1,6},\d{1,2}>")

def _krc_segments(data):
    """把全库 KRC 正文按位置聚类成段(相邻<1000B 视为同一首歌的歌词)"""
    heads = [m.start() for m in _KRC_HEAD.finditer(data)]
    segs = []
    for h in heads:
        if segs and h - segs[-1][1] < 1000:
            segs[-1][1] = h
        else:
            segs.append([h, h])
    return segs

def scan_db_wide(db_path=DB_PATH):
    """宽索引: 扫所有 KRC 正文段(不依赖 krck 键), 返回 {track_id: lrc}
    汽水歌词记录有两种: krck 标记的(少数) 和 rc/content 类型的(大多数),
    后者没有 krck 键, 只能靠 KRC 正文特征定位。"""
    if not os.path.exists(db_path):
        return {}
    data = open(db_path, "rb").read()
    out = {}
    for s, e in _krc_segments(data):
        raw = _parse_str_before(data, e + 200)
        if not raw:
            raw = data[s:e + 600]
        tid_ms = _TRACK_ID.findall(data[max(0, s - 4000):e + 4000])
        if not tid_ms:
            continue
        tid = tid_ms[0].decode()
        lrc = _krc_to_lrc(raw)
        if len(lrc) > len(out.get(tid, "")):
            out[tid] = lrc
    return out

def _title_candidates(data, title, back=2500, fwd=2500):
    """歌名在 db 中出现位置附近的 track_id 候选(按出现次数排序)"""
    from collections import Counter
    cnt = Counter()
    for m in re.finditer(re.escape(title), data):
        seg = data[max(0, m.start() - back):m.start() + fwd]
        for tid in _TRACK_ID.findall(seg):
            cnt[tid.decode()] += 1
    return [t for t, _ in cnt.most_common()]

def local_lyrics(title, artist="", album="", db_path=DB_PATH):
    """按 歌名(+歌手) 从本地缓存找歌词, 返回 LRC 文本或 ''
    两级索引: 先精确 krck 索引, 未命中再走宽索引(rc/content 类型记录)"""
    if not (title and os.path.exists(db_path)):
        return ""
    data = open(db_path, "rb").read()
    index = scan_db(db_path)
    artist_b = artist.encode() if artist else b""

    def cjk(s):
        return sum(1 for ch in s if "\u4e00" <= ch <= "\u9fff")

    wide = None  # 惰性: 只在精确索引未命中时才扫宽索引

    for tid in _title_candidates(data, title.encode()):
        entry = index.get(tid)
        if entry:
            krc, line = entry.get("krc_lrc", ""), entry.get("line_lrc", "")
            lyric = line if cjk(line) >= cjk(krc) else krc
            if len(lyric) > 30 and _artist_ok(data, tid, artist_b):
                return lyric
        # 宽索引兜底
        if wide is None:
            wide = scan_db_wide(db_path)
        lyric = wide.get(tid, "")
        if len(lyric) > 30 and _artist_ok(data, tid, artist_b):
            return lyric
    return ""

def _artist_ok(data, tid, artist_b):
    """歌手辅助校验: tid 出现处附近应能找到歌手名; 无歌手要求则放行。
    多歌手(如 '克里, 丝绒月亮')在库里可能分开存储, 拆开任一命中即算过"""
    if not artist_b:
        return True
    parts = [p.strip() for p in re.split(r"[,，/、&]", artist_b.decode("utf-8", "ignore")) if p.strip()]
    for m in re.finditer(re.escape(tid.encode()), data):
        ctx = data[m.start():m.start() + 4000]
        if all(p.encode() in ctx for p in parts):
            return True
        if any(p.encode() in ctx for p in parts) and len(parts) == 1:
            return True
    return False

if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        t, a = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
        lyr = local_lyrics(t, a)
        print(lyr if lyr else "本地缓存未找到")
    else:
        idx = scan_db()
        print(f"本地歌词缓存共 {len(idx)} 首 (track_id)")
        for tid, e in list(idx.items())[:5]:
            first = (e.get("line_lrc") or e.get("krc_lrc") or "").split("\n")[0]
            print(f"  {tid}  专辑={e.get('album','?')}  {first[:40]}")
