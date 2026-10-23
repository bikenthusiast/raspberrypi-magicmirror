#!/usr/bin/env python3
"""gesture.py -- live swipe detection on the SEN0628 (4x4 zones).

Live:    python3 scripts/gesture.py            (prints SWIPE_LEFT / SWIPE_RIGHT)
         python3 scripts/gesture.py -v         (also prints a line per frame)
         python3 scripts/gesture.py --exec 'echo {gesture}'   (run a command per swipe)
Capture: python3 scripts/gesture.py --capture data/capture
         Enter = a swipe was missed, f = the last detection was false.
         Saves the last seconds of sensor data to data/capture/{missed,false,detected}/
Replay:  python3 scripts/gesture.py --replay data/gestures_v2/*/*.jsonl

How it works
  1. Background: every zone keeps a slowly adapting distance (body, room).
     It only adapts while the zone is NOT covered by a hand; a zone that stays
     "hand" longer than --absorb seconds is taken over as background (static object).
  2. Hand zone: closer than --near mm AND at least --delta mm in front of its background.
  3. Position: mean column of the hand zones, 0..1 across the field (needs >= --min-zones zones).
  4. Swipe: the position moves >= --travel (fraction of the field width) within --window seconds.
     Afterwards the detector is locked for --lockout seconds.

Orientation (USB-C facing down, sensor facing the user): the image is mirrored,
column 1 is the user's right -> increasing column = SWIPE_LEFT. Use --axis row
if the sensor is rotated by 90 deg, --invert if left/right come out swapped.
"""

import argparse
import collections
import json
import shlex
import subprocess
import sys
import time

INVALID = 4000


class SwipeDetector:
    def __init__(self, near=1000, delta=60, min_zones=3, travel=0.35, window=1.8,
                 lockout=1.5, alpha=0.05, absorb=3.0, axis="col", invert=False, size=4,
                 band=None, pushpull=True, push_delta=250, push_window=1.0, push_max_zones=6,
                 push_max_lat=0.20):
        self.near, self.delta, self.min_zones = near, delta, min_zones
        self.travel, self.window, self.lockout = travel, window, lockout
        self.alpha, self.absorb = alpha, absorb
        self.axis, self.invert, self.size = axis, invert, size
        # band: only the zones within `band` mm of the nearest foreground zone count as hand
        # (separates the hand from a closer-than-background arm or body). None = off.
        self.band = band
        # push/pull: a compact hand (<= push_max_zones, i.e. not a body/arm) whose
        # nearest distance changes by >= push_delta mm within push_window s, with
        # little lateral travel. The baseline reseeds every time the hand (re)appears,
        # so the onset of a hand is never itself a push, and a slow body approach
        # (many zones from the start) never seeds.
        self.pushpull = pushpull
        self.push_delta, self.push_window, self.push_max_zones = push_delta, push_window, push_max_zones
        self.push_max_lat = push_max_lat
        self.bg = None
        self.hand_since = [None] * size * size
        self.hist = collections.deque()
        self.dmin_hist = collections.deque()
        self.locked_until = 0.0

    def _pos(self, i):
        """Zone position across the swipe axis, normalised to 0..1 (independent of 4x4/8x8)."""
        k = i % self.size if self.axis == "col" else i // self.size
        return (k + 0.5) / self.size

    def update(self, t, mm):
        """Feed one frame (timestamp in s, distances in mm). Returns 'SWIPE_LEFT',
        'SWIPE_RIGHT' or None, plus a small info dict."""
        if self.bg is None:
            self.size = int(round(len(mm) ** 0.5))
            self.hand_since = [None] * len(mm)
            self.bg = [float(v) for v in mm]
        hand = []
        for i, d in enumerate(mm):
            b = self.bg[i]
            is_hand = d < INVALID and d <= self.near and (b >= INVALID or b - d >= self.delta)
            if is_hand:
                if self.hand_since[i] is None:
                    self.hand_since[i] = t
                elif t - self.hand_since[i] > self.absorb:      # static object -> background
                    self.bg[i] = float(d)
                    self.hand_since[i] = None
                    is_hand = False
            else:
                self.hand_since[i] = None
                target = INVALID if d >= INVALID else d
                self.bg[i] += self.alpha * (target - b)
            if is_hand:
                hand.append(i)

        hand_dmin = min((mm[i] for i in hand), default=None)
        if self.band is not None and hand:
            hand = [i for i in hand if mm[i] <= hand_dmin + self.band]
        info = {"zones": len(hand), "pos": None, "dmin": hand_dmin}
        if t < self.locked_until:
            return None, info

        # --- lateral swipe (unchanged) ---
        if len(hand) >= self.min_zones:
            pos = sum(self._pos(i) for i in hand) / len(hand)
            info["pos"] = pos
            self.hist.append((t, pos))
        while self.hist and t - self.hist[0][0] > self.window:
            self.hist.popleft()
        if len(self.hist) >= 2:
            p_now = self.hist[-1][1]
            for _, p_old in self.hist:
                move = p_now - p_old
                if abs(move) >= self.travel:
                    left = (move > 0) != self.invert
                    self.hist.clear()
                    self.dmin_hist.clear()
                    self.locked_until = t + self.lockout
                    return ("SWIPE_LEFT" if left else "SWIPE_RIGHT"), info

        # --- push / pull (distance change of a hand) ---
        # Seed the baseline only on a compact (hand-like, not body) frame; once
        # seeded, keep tracking even as the hand comes close and fills more zones
        # (a flat hand at 1-2 cm covers every zone). A body approach starts with
        # many zones, so it never seeds.
        if (self.pushpull and hand_dmin is not None and len(hand) >= 1
                and (self.dmin_hist or len(hand) <= self.push_max_zones)):
            pos_all = sum(self._pos(i) for i in hand) / len(hand)
            self.dmin_hist.append((t, hand_dmin, pos_all))
            while self.dmin_hist and t - self.dmin_hist[0][0] > self.push_window:
                self.dmin_hist.popleft()
            # Decide only once the window is essentially full, so a swipe (which
            # moves laterally within this time) is recognised first and the lateral
            # guard can see its movement. The candidate drop/lat are exposed in
            # `info` for live tuning (shown by -v as pd=/pl=).
            if len(self.dmin_hist) >= 2:
                span = t - self.dmin_hist[0][0]
                d_old = self.dmin_hist[0][1]
                # Net lateral displacement (not peak-to-peak): the mean centroid of
                # the newest vs. the oldest frames. A centred push/pull nets ~0 even
                # though the coarse 1-3 zone centroid jitters frame to frame; a swipe
                # nets a large value. Robust where peak-to-peak was not.
                poss = [p for _, _, p in self.dmin_hist]
                k = max(1, len(poss) // 4)
                lat = abs(sum(poss[-k:]) / k - sum(poss[:k]) / k)
                drop = d_old - hand_dmin  # +ve: moved closer (push), -ve: moved away (pull)
                # Suppress while a lateral swipe is building: the swipe history uses
                # the steadier >=min_zones centroid, so this kills swipe-onset false
                # pushes without touching a real (few-zone, centred) push.
                swipe_lat = 0.0
                if len(self.hist) >= 2:
                    ps = [p for _, p in self.hist]
                    swipe_lat = max(ps) - min(ps)
                info["pd"], info["pl"] = int(drop), round(lat, 2)
                if (span >= self.push_window * 0.8 and lat <= self.push_max_lat
                        and swipe_lat <= self.push_max_lat and abs(drop) >= self.push_delta):
                    self.dmin_hist.clear()
                    self.hist.clear()
                    self.locked_until = t + self.lockout
                    return ("PUSH" if drop > 0 else "PULL"), info
        else:
            self.dmin_hist.clear()
        return None, info


def make_detector(a):
    return SwipeDetector(near=a.near, delta=a.delta, min_zones=a.min_zones, travel=a.travel,
                         window=a.window, lockout=a.lockout, alpha=a.alpha, absorb=a.absorb,
                         axis=a.axis, invert=a.invert, band=a.band,
                         pushpull=not a.no_pushpull, push_delta=a.push_delta,
                         push_window=a.push_window, push_max_zones=a.push_max_zones,
                         push_max_lat=a.push_max_lat)


def replay(a):
    stats = collections.Counter()
    for path in a.replay:
        with open(path) as f:
            meta = json.loads(f.readline())
            frames = [json.loads(line) for line in f]
        det = make_detector(a)
        events = []
        for fr in frames:
            ev, _ = det.update(fr["t"], fr["mm"])
            if ev:
                events.append(f"{ev}@{fr['t']:.2f}")
        label = meta["label"]
        expect = {"swipe_left": "SWIPE_LEFT", "swipe_right": "SWIPE_RIGHT"}.get(label)
        names = [e.split("@")[0] for e in events]
        if label in ("missed", "detected"):      # capture: a swipe happened, direction unknown
            ok = bool(events)
        elif expect is None:                     # none, false: nothing should trigger
            ok = not events
        else:
            ok = names[:1] == [expect]
        stats[(label, ok)] += 1
        if a.verbose or not ok:
            print(f"{'ok ' if ok else 'BAD'} {label:11} {path.split('/')[-1]}  {' '.join(events) or '-'}")
    print()
    for label in sorted({k[0] for k in stats}):
        good, bad = stats[(label, True)], stats[(label, False)]
        print(f"{label:11} {good}/{good + bad} correct")


class Capture:
    """Ring buffer of recent frames, written to disk on demand (--capture)."""

    def __init__(self, folder, seconds, params):
        import pathlib
        self.root = pathlib.Path(folder)
        self.seconds = seconds
        self.params = params
        self.buf = collections.deque()
        self.pending = None            # (due time, gesture) -- save a bit after a detection
        self.last_detect = None        # (path, gesture, time) of the last saved detection

    def add(self, t, mm):
        self.buf.append((t, list(mm)))
        while self.buf and t - self.buf[0][0] > self.seconds:
            self.buf.popleft()
        if self.pending and t >= self.pending[0]:
            gesture = self.pending[1]
            self.pending = None
            path = self.save("detected", gesture)
            self.last_detect = (path, gesture, t)

    def detected(self, t, gesture):
        # wait 0.5 s so the take also shows the hand leaving the field
        self.pending = (t + 0.5, gesture)

    def save(self, label, gesture=None):
        if not self.buf:
            return None
        folder = self.root / label
        folder.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        path = folder / f"{stamp}.jsonl"
        n = 1
        while path.exists():
            n += 1
            path = folder / f"{stamp}_{n}.jsonl"
        t0 = self.buf[0][0]
        meta = {"label": label, "gesture": gesture, "size": int(round(len(self.buf[0][1]) ** 0.5)),
                "duration": round(self.buf[-1][0] - t0, 2),
                "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "frames": len(self.buf), "misses": 0, "params": self.params}
        with path.open("w") as f:
            f.write(json.dumps(meta) + "\n")
            for t, mm in self.buf:
                f.write(json.dumps({"t": round(t - t0, 3), "mm": mm}) + "\n")
        return path

    def mark_false(self, now):
        """Move the last detection (if recent) from detected/ to false/."""
        if self.pending:                     # detection not yet written: write it as false
            gesture = self.pending[1]
            self.pending = None
            return self.save("false", gesture)
        if not self.last_detect or now - self.last_detect[2] > 15:
            return None
        src, gesture, _ = self.last_detect
        self.last_detect = None
        lines = src.read_text().splitlines()
        meta = json.loads(lines[0])
        meta["label"] = "false"
        dst = self.root / "false" / src.name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text("\n".join([json.dumps(meta)] + lines[1:]) + "\n")
        src.unlink()
        return dst


class Keys:
    """Single key presses without Enter-buffering (only if stdin is a terminal)."""

    def __init__(self):
        self.ok = sys.stdin.isatty()
        if self.ok:
            import termios
            import tty
            self.fd = sys.stdin.fileno()
            self.old = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)

    def get(self):
        if not self.ok:
            return None
        import select
        if select.select([sys.stdin], [], [], 0)[0]:
            return sys.stdin.read(1)
        return None

    def restore(self):
        if self.ok:
            import termios
            termios.tcsetattr(self.fd, termios.TCSADRAIN, self.old)


def live(a):
    from sen0628 import SEN0628
    tof = SEN0628(a.port)
    print(f"Setting {a.size}x{a.size} mode (5 s) ...")
    if not tof.set_mode(a.size):
        sys.exit("sensor does not answer -- check wiring, UART lever, power cycle")
    det = make_detector(a)
    cap = keys = None
    if a.capture:
        params = {k: getattr(a, k) for k in ("near", "delta", "min_zones", "travel", "window",
                                             "alpha", "absorb", "axis", "invert")}
        cap = Capture(a.capture, a.capture_seconds, params)
        keys = Keys()
        if not keys.ok:
            print("capture: stdin is not a terminal -- only detections are saved")
        print(f"Capture to {a.capture}/  --  Enter = swipe missed, f = last detection false",
              flush=True)
    print("Ready. Swipe in front of the sensor (Ctrl+C to stop).", flush=True)
    try:
        while True:
            if keys:
                k = keys.get()
                if k in ("\n", "\r"):
                    path = cap.save("missed")
                    print(f"{time.strftime('%H:%M:%S')}  saved MISSED  {path}", flush=True)
                elif k in ("f", "F"):
                    path = cap.mark_false(time.monotonic())
                    print(f"{time.strftime('%H:%M:%S')}  " +
                          (f"saved FALSE   {path}" if path else "no recent detection to mark"),
                          flush=True)
            mm = tof.frame()
            if mm is None:
                continue
            t = time.monotonic()
            if cap:
                cap.add(t, mm)
            ev, info = det.update(t, mm)
            if ev and cap:
                cap.detected(t, ev)
            if a.verbose:
                pos = f"{info['pos']:.2f}" if info["pos"] else "  - "
                dmin = f"{info['dmin']:4d}" if info.get("dmin") is not None else "   -"
                push = f" pd={info['pd']:+5d} pl={info['pl']:.2f}" if "pd" in info else ""
                print(f"zones={info['zones']:2d} pos={pos} dmin={dmin}{push}  " +
                      " ".join("  .." if v >= INVALID else f"{v // 10:4d}" for v in mm))
            if ev:
                print(f"{time.strftime('%H:%M:%S')}  {ev}", flush=True)
                if a.exec:
                    try:
                        subprocess.Popen(shlex.split(a.exec.format(gesture=ev)))
                    except OSError as e:          # missing script, not executable
                        print(f"exec failed: {e}", flush=True)
    except KeyboardInterrupt:
        print()
    finally:
        if keys:
            keys.restore()


def main():
    p = argparse.ArgumentParser(description="SEN0628 swipe detector")
    p.add_argument("--port", default="/dev/ttyAMA5")
    p.add_argument("--size", type=int, choices=(4, 8), default=4, help="zones per side (4)")
    p.add_argument("--replay", nargs="+", metavar="JSONL", help="run on recorded takes instead of the sensor")
    p.add_argument("--exec", help="command per gesture, {gesture} is replaced, e.g. 'echo {gesture}'")
    p.add_argument("--capture", metavar="DIR", help="save takes: Enter = missed, f = false detection")
    p.add_argument("--capture-seconds", type=float, default=4.0, help="seconds kept per capture (4)")
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument("--axis", choices=("col", "row"), default="col")
    p.add_argument("--invert", action="store_true", help="swap left/right")
    p.add_argument("--near", type=int, default=1000, help="max hand distance in mm (1000)")
    p.add_argument("--delta", type=int, default=60, help="min mm in front of background (60)")
    p.add_argument("--band", type=int, default=None, help="mm around the nearest zone that count as hand (off)")
    p.add_argument("--min-zones", type=int, default=3, help="min hand zones per frame (3)")
    p.add_argument("--travel", type=float, default=0.35, help="min movement as fraction of the field width (0.35)")
    p.add_argument("--window", type=float, default=1.8, help="max swipe duration in s (1.8)")
    p.add_argument("--lockout", type=float, default=1.5, help="pause after a swipe in s (1.5)")
    p.add_argument("--alpha", type=float, default=0.05, help="background adaptation per frame (0.05)")
    p.add_argument("--absorb", type=float, default=3.0, help="s until a static object becomes background (3)")
    p.add_argument("--no-pushpull", action="store_true", help="disable PUSH/PULL detection")
    p.add_argument("--push-delta", type=int, default=250,
                   help="min mm the hand must move toward/away within the window (250)")
    p.add_argument("--push-window", type=float, default=1.0, help="push/pull measurement window in s (1.0)")
    p.add_argument("--push-max-zones", type=int, default=6,
                   help="max hand zones for push/pull (above this = body/arm, ignored) (6)")
    p.add_argument("--push-max-lat", type=float, default=0.20,
                   help="max net lateral displacement (0..1) allowed during a push/pull (0.20)")
    a = p.parse_args()
    replay(a) if a.replay else live(a)


if __name__ == "__main__":
    main()
