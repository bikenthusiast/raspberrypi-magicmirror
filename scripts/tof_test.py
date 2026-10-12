#!/usr/bin/env python3
"""tof_test.py -- print SEN0628 frames as a grid and show the frame rate."""

import argparse
import time

from sen0628 import SEN0628

p = argparse.ArgumentParser()
p.add_argument("--port", default="/dev/ttyAMA5")
p.add_argument("--size", type=int, choices=(4, 8), default=4)
args = p.parse_args()

tof = SEN0628(args.port)
if not tof.set_mode(args.size):
    raise SystemExit("sensor does not answer -- mode switch on UART? wiring? power-cycled?")

t0, frames = time.monotonic(), 0
while True:
    mm = tof.frame()
    if mm is None:
        print("incomplete frame")
        continue
    for r in range(args.size):
        print(" ".join(f"{v:4d}" for v in mm[r * args.size:(r + 1) * args.size]))
    frames += 1
    print(f"--- frame {frames}, {frames / (time.monotonic() - t0):.1f} fps")
