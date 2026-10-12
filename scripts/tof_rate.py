#!/usr/bin/env python3
"""Find out why tof_record.py runs at ~17 fps while tof_bench.py reaches 25 fps.

Run 1 showed: mode order and scene make no difference (all ~60 ms).
Run 2 checks the remaining difference to tof_bench.py: the byte gap used
for the mode switch (bench: 1 ms) and for the first frames after it.
"""
import statistics
import sys
import time

from sen0628 import SEN0628

N = 75


def measure(tof, label):
    tof.ser.reset_input_buffer()
    ts, fails, invalid = [], 0, []
    while len(ts) < N and fails < 10:
        f = tof.frame()
        if f is None:
            fails += 1
            continue
        ts.append(time.monotonic())
        invalid.append(sum(v >= 4000 for v in f))
    d = [1000 * (b - a) for a, b in zip(ts[5:], ts[6:], strict=False)]   # skip warm-up frames
    print(f"{label:<34} {len(d) and 1000/statistics.median(d):5.1f} fps   "
          f"median {statistics.median(d):5.1f} ms   min {min(d):5.1f}   max {max(d):6.1f}   "
          f"fails {fails}   invalid zones {statistics.median(invalid):.0f}/16")


tof = SEN0628(sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyAMA5")

print("Same scene for all runs.\n")

# A: what tof_record.py / previous tof_rate.py do
tof.byte_gap = 0.0002
if not tof.set_mode(4):
    sys.exit("no answer to mode switch")
measure(tof, "A  set_mode gap 0.2 ms, frames 0.2")

# D: mode switch with 1 ms byte gap (as tof_bench.py), frames at 0.2 ms
tof.byte_gap = 0.001
tof.set_mode(4)
tof.byte_gap = 0.0002
measure(tof, "D  set_mode gap 1.0 ms, frames 0.2")

# E: exact tof_bench.py sequence: 1 ms gap for switch AND first frames
tof.byte_gap = 0.001
tof.set_mode(4)
measure(tof, "E1 set_mode gap 1.0 ms, frames 1.0")
tof.byte_gap = 0.0002
measure(tof, "E2 ... then frames 0.2")
