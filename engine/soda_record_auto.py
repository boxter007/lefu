#!/usr/bin/env python3
# soda_record_auto.py — 自动值守录制
# 用法: python3 soda_record_auto.py <输出wav> [检查间隔秒=300] [静音阈值dB=-60] [连续静音上限=2]
# 逻辑: 持续录音; 每个检查周期评估该周期内音频峰值电平;
#       低于阈值为"无声", 连续2个周期无声 → 自动停止并保存
import sys, os, wave, queue, time, threading
from collections import deque
import numpy as np
import sounddevice as sd

SR = 48000
CH = 2

def main():
    out = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 300.0
    th_db = float(sys.argv[3]) if len(sys.argv) > 3 else -60.0
    max_streak = int(sys.argv[4]) if len(sys.argv) > 4 else 2

    devs = sd.query_devices()
    idx = next(i for i, d in enumerate(devs)
               if "BlackHole 2ch" in d["name"] and d["max_input_channels"] >= 2)

    q = queue.Queue()
    rms_log = deque()
    stop_flag = threading.Event()
    t0 = time.time()

    def callback(indata, frames, t, status):
        rms = 20 * np.log10(np.sqrt((indata.astype(np.float64) ** 2).mean()) + 1e-12)
        rms_log.append((time.time(), rms))
        if len(rms_log) > 20000:
            for _ in range(5000):
                rms_log.popleft()
        q.put(indata.copy())

    def checker():
        streak = 0
        time.sleep(interval)
        while not stop_flag.is_set():
            now = time.time()
            recent = [r for t, r in rms_log if t > now - interval]
            peak = max(recent) if recent else -120.0
            if peak < th_db:
                streak += 1
                print(f"[{time.time()-t0:.0f}s] 检查: 无声(峰值{peak:.1f}dB < {th_db}dB) 连续第{streak}/{max_streak}次", flush=True)
                if streak >= max_streak:
                    print("连续无声达标, 停止录制", flush=True)
                    stop_flag.set()
                    return
            else:
                streak = 0
                print(f"[{time.time()-t0:.0f}s] 检查: 音乐正常(峰值{peak:.1f}dB)", flush=True)
            time.sleep(interval)

    threading.Thread(target=checker, daemon=True).start()

    w = wave.open(out, "wb")
    w.setnchannels(CH); w.setsampwidth(2); w.setframerate(SR)
    frames = 0
    print(f"值守录制中 → {out}  (每{interval:.0f}s体检, 连续{max_streak}次无声自动停)", flush=True)
    with sd.InputStream(samplerate=SR, channels=CH, device=idx,
                        dtype="int16", callback=callback, blocksize=0):
        # 真实开录时刻落盘, 供切歌脚本精确对齐时间轴 offset
        start_epoch = time.time()
        try:
            with open(out + ".epoch", "w") as ef:
                ef.write(str(start_epoch))
            print(f"开录基准 epoch: {start_epoch:.1f} → {out}.epoch", flush=True)
        except Exception as e:
            print(f"[警告] epoch 落盘失败: {e}", flush=True)
        try:
            while not stop_flag.is_set():
                try:
                    data = q.get(timeout=0.5)
                    w.writeframes(data.tobytes())
                    frames += len(data)
                except queue.Empty:
                    continue
        except KeyboardInterrupt:
            pass
    w.close()
    print(f"已保存: {out} ({frames/SR/60:.1f} 分钟)", flush=True)

if __name__ == "__main__":
    main()
