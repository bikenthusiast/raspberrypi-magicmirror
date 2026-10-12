#!/usr/bin/env python3
"""
tof_record.py -- record labelled SEN0628 gesture takes for development

Each take is one short recording (default 2.5 s) of one gesture, saved as
its own JSON-lines file:

    data/gestures/<label>/<YYYYmmdd-HHMMSS>_<nn>.jsonl

    line 1   {"label": ..., "size": 4, "duration": 2.5, "started": "...", ...}
    line 2+  {"t": 0.043, "mm": [16 distances in mm, row by row]}

"t" is seconds since the start of the take. 4000 = invalid zone.

Usage examples
    python3 scripts/tof_record.py swipe_right            # 10 takes, 4x4
    python3 scripts/tof_record.py swipe_left --takes 15
    python3 scripts/tof_record.py none --takes 3 --duration 20   # background
    python3 scripts/tof_record.py push --size 8 --preview
"""

import argparse
import datetime as dt
import json
import pathlib
import sys
import time

from sen0628 import SEN0628

LABELS = ("swipe_left", "swipe_right", "swipe_up", "swipe_down", "push", "none")
INVALID = 4000


def grid_line(mm, size, near=600):
    """One-line preview: '#' for zones closer than `near` mm, '.' otherwise."""
    rows = []
    for r in range(size):
        rows.append("".join("#" if v < near else "." for v in mm[r * size:(r + 1) * size]))
    valid = [v for v in mm if v < INVALID]
    closest = min(valid) if valid else INVALID
    return " | ".join(rows) + f"   nearest {closest:4d} mm"


def countdown(seconds=3):
    for n in range(seconds, 0, -1):
        print(f"  {n} ...", end="\r", flush=True)
        time.sleep(0.7)
    print("  GO!     ")


def record_take(tof, duration, preview):
    tof.ser.reset_input_buffer()
    frames, misses = [], 0
    t0 = time.monotonic()
    while (now := time.monotonic()) - t0 < duration:
        mm = tof.frame()
        if mm is None:
            misses += 1
            continue
        frames.append({"t": round(now - t0, 3), "mm": list(mm)})
        if preview:
            print("  " + grid_line(mm, tof.size), flush=True)
    return frames, misses


def main():
    p = argparse.ArgumentParser(description="Record labelled SEN0628 gesture takes.")
    p.add_argument("label", choices=LABELS)
    p.add_argument("--takes", type=int, default=10, help="number of takes (default 10)")
    p.add_argument("--duration", type=float, default=2.5, help="seconds per take (default 2.5)")
    p.add_argument("--size", type=int, choices=(4, 8), default=4, help="zones per side (default 4)")
    p.add_argument("--out", default="data/gestures", help="output folder")
    p.add_argument("--port", default="/dev/ttyAMA5")
    p.add_argument("--preview", action="store_true", help="print each frame while recording")
    p.add_argument("--yes", action="store_true", help="keep every take without asking")
    a = p.parse_args()

    out = pathlib.Path(a.out) / a.label
    out.mkdir(parents=True, exist_ok=True)
    session = dt.datetime.now().strftime("%Y%m%d-%H%M%S")

    tof = SEN0628(a.port)
    print(f"Setting {a.size}x{a.size} mode (5 s) ...")
    if not tof.set_mode(a.size):
        sys.exit("sensor does not answer -- check wiring, UART lever, power cycle")

    kept = 0
    for i in range(1, a.takes + 1):
        input(f"\nTake {i}/{a.takes} '{a.label}' -- hand ready, press Enter ")
        countdown()
        frames, misses = record_take(tof, a.duration, a.preview)
        fps = len(frames) / a.duration
        print(f"  {len(frames)} frames, {fps:.1f} fps, {misses} misses")
        if not a.yes:
            ans = input("  keep? [Y/n] ").strip().lower()
            if ans.startswith("n"):
                print("  discarded")
                continue
        path = out / f"{session}_{i:02d}.jsonl"
        meta = {"label": a.label, "size": a.size, "duration": a.duration,
                "started": dt.datetime.now().isoformat(timespec="seconds"),
                "frames": len(frames), "misses": misses}
        with path.open("w") as f:
            f.write(json.dumps(meta) + "\n")
            for fr in frames:
                f.write(json.dumps(fr) + "\n")
        kept += 1
        print(f"  saved {path}")

    print(f"\nDone: {kept} of {a.takes} takes kept in {out}/")


if __name__ == "__main__":
    main()
