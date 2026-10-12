"""Regression tests for the rule-based swipe detector in scripts/gesture.py.

Run:  python3 -m pytest tests/

The fixtures in tests/fixtures/tof/ are real SEN0628 recordings (4x4 zones,
USB-C facing down, hand at close range), five takes per class from the v2
session documented in docs/sen0628.md. They contain distances only.

The thresholds below are the replay result of the current defaults, minus
nothing: a change to the detector that loses a swipe or adds a false
trigger fails here before it reaches the wall.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from gesture import INVALID, SwipeDetector  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures" / "tof"
EXPECT = {"swipe_left": "SWIPE_LEFT", "swipe_right": "SWIPE_RIGHT", "none": None}


def load(path: Path) -> tuple[dict, list[dict]]:
    lines = path.read_text().splitlines()
    return json.loads(lines[0]), [json.loads(line) for line in lines[1:]]


def events(frames: list[dict], **params) -> list[str]:
    det = SwipeDetector(**params)
    out = []
    for fr in frames:
        ev, _ = det.update(fr["t"], fr["mm"])
        if ev:
            out.append(ev)
    return out


def takes(label: str) -> list[Path]:
    files = sorted((FIXTURES / label).glob("*.jsonl"))
    assert files, f"no fixtures for {label}"
    return files


@pytest.mark.parametrize("label,minimum", [("swipe_left", 4), ("swipe_right", 4)])
def test_swipes_are_recognised_in_the_right_direction(label, minimum):
    results = [events(load(p)[1]) for p in takes(label)]
    correct = sum(r[:1] == [EXPECT[label]] for r in results)
    wrong = sum(bool(r) and r[0] != EXPECT[label] for r in results)
    assert wrong == 0, f"{label}: {wrong} take(s) detected in the wrong direction"
    assert correct >= minimum, f"{label}: only {correct}/{len(results)} recognised"


def test_no_false_trigger_on_none():
    for p in takes("none"):
        assert events(load(p)[1]) == [], f"false trigger in {p.name}"


def test_mirroring_the_columns_swaps_the_direction():
    """The sensor image is mirrored (column 1 = user's right). Flipping the
    columns of a left swipe must turn it into a right swipe."""
    def flip(mm):
        return [mm[r * 4 + (3 - c)] for r in range(4) for c in range(4)]

    for p in takes("swipe_left"):
        frames = load(p)[1]
        original = events(frames)
        if original[:1] != ["SWIPE_LEFT"]:
            continue
        flipped = [{"t": f["t"], "mm": flip(f["mm"])} for f in frames]
        assert events(flipped)[:1] == ["SWIPE_RIGHT"], p.name


def test_lockout_allows_only_one_event_per_swipe():
    for p in takes("swipe_left") + takes("swipe_right"):
        assert len(events(load(p)[1])) <= 1, p.name


def test_static_object_is_absorbed_into_the_background():
    """Something placed in front of the sensor and left there must not
    trigger, and must stop counting as a hand after `absorb` seconds."""
    det = SwipeDetector(absorb=1.0)
    empty = [INVALID] * 16
    object_ = [INVALID] * 16
    object_[5] = object_[6] = object_[9] = 300
    t = 0.0
    for _ in range(20):
        det.update(t, empty)
        t += 0.06
    zones = []
    for _ in range(40):
        ev, info = det.update(t, object_)
        assert ev is None
        zones.append(info["zones"])
        t += 0.06
    assert zones[0] > 0 and zones[-1] == 0
