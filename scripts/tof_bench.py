#!/usr/bin/env python3
"""
tof_bench.py -- measure the SEN0628 frame rate over UART

Varies the byte gap and the zone count, without printing frames, and
reports per variant:
    fps          frames per second actually delivered
    dup %        share of frames identical to the previous one
                 (> 0 means we poll faster than the sensor measures)
    fail         requests without a valid answer
"""

import statistics
import time

from sen0628 import SEN0628

N = 60
GAPS_MS = (1.0, 0.5, 0.2, 0.0)

tof = SEN0628("/dev/ttyAMA5")
print(f"{'zones':>5} {'gap ms':>6} {'fps':>6} {'mean ms':>8} {'max ms':>7} {'dup %':>6} {'fail':>5}")
for size in (8, 4):
    tof.byte_gap = 0.001
    if not tof.set_mode(size):
        print(f"{size}x{size}: no answer to mode switch")
        continue
    for gap in GAPS_MS:
        tof.byte_gap = gap / 1000
        intervals, dups, fails, prev = [], 0, 0, None
        t_last = time.monotonic()
        t0 = t_last
        got = 0
        while got < N and fails < N:
            f = tof.frame()
            now = time.monotonic()
            if f is None:
                fails += 1
                continue
            intervals.append(now - t_last)
            t_last = now
            dups += f == prev
            prev = f
            got += 1
        if not intervals:
            print(f"{size}x{size:<3} {gap:6.1f}   no valid frames")
            continue
        fps = got / (time.monotonic() - t0)
        print(f"{size}x{size:<3} {gap:6.1f} {fps:6.1f} {1000*statistics.mean(intervals):8.1f} "
              f"{1000*max(intervals):7.1f} {100*dups/got:6.1f} {fails:5d}")
