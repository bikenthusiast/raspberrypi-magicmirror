"""Tests for scripts/edge_bridge.py -- no broker, no mirror.

Run on the Mac or the Pi:  python3 -m pytest tests/

The gesture payload comes from tests/fixtures/gesture_v1.json, an exact copy
of pi-edge-ai's tests/fixtures/contract/gesture_v1.json. If the producer
changes the contract, this copy changes with it -- and these tests say what
breaks on the mirror side.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import edge_bridge as eb

FIXTURE = Path(__file__).parent / "fixtures" / "gesture_v1.json"
CONTRACT = json.loads(FIXTURE.read_text())
SENT_AT = datetime.fromisoformat(CONTRACT["ts"])
ONLINE = json.dumps({"v": 1, "online": True}).encode()
OFFLINE = json.dumps({"v": 1, "online": False}).encode()


def gesture(**overrides) -> bytes:
    return json.dumps({**CONTRACT, **overrides}).encode()


@pytest.fixture
def bridge() -> eb.Bridge:
    b = eb.Bridge(eb.Config(actions=eb.parse_actions("swipe_up=show,swipe_down=hide")))
    b.handle("edge/mirror/status", ONLINE, now=SENT_AT, monotonic=0.0)
    return b


def send(b: eb.Bridge, payload: bytes, *, after_s: float = 0.5,
         monotonic: float = 100.0, topic: str = "edge/mirror/gesture"):
    return b.handle(topic, payload, now=SENT_AT + timedelta(seconds=after_s),
                    monotonic=monotonic)


def test_contract_fixture_opens_the_guest_page(bridge):
    decision = send(bridge, FIXTURE.read_bytes())
    assert decision.action == "show"


def test_swipe_down_closes_it(bridge):
    assert send(bridge, gesture(id=8, gesture="swipe_down")).action == "hide"


def test_nothing_happens_while_the_producer_is_offline(bridge):
    bridge.handle("edge/mirror/status", OFFLINE, now=SENT_AT, monotonic=0.0)
    decision = send(bridge, FIXTURE.read_bytes())
    assert decision.action is None and "not online" in decision.reason


def test_unknown_device_counts_as_offline(bridge):
    decision = send(bridge, FIXTURE.read_bytes(), topic="edge/other/gesture")
    assert decision.action is None


def test_stale_redelivery_is_dropped(bridge):
    decision = send(bridge, FIXTURE.read_bytes(), after_s=300)
    assert decision.action is None and "stale" in decision.reason


def test_duplicate_id_is_dropped(bridge):
    assert send(bridge, FIXTURE.read_bytes(), monotonic=100).action == "show"
    second = send(bridge, FIXTURE.read_bytes(), monotonic=200)
    assert second.action is None and "duplicate" in second.reason


def test_the_same_action_is_rate_limited(bridge):
    assert send(bridge, gesture(id=1), monotonic=100.0).action == "show"
    assert send(bridge, gesture(id=2), monotonic=100.5).action is None
    assert send(bridge, gesture(id=3), monotonic=103.0).action == "show"


def test_hide_right_after_show_is_allowed(bridge):
    assert send(bridge, gesture(id=1), monotonic=100.0).action == "show"
    down = gesture(id=2, gesture="swipe_down")
    assert send(bridge, down, monotonic=100.5).action == "hide"


def test_unknown_schema_version_is_ignored(bridge):
    decision = send(bridge, gesture(v=2))
    assert decision.action is None and "schema" in decision.reason


def test_unmapped_or_new_gesture_does_nothing(bridge):
    assert send(bridge, gesture(gesture="swipe_left")).action is None
    assert send(bridge, gesture(id=99, gesture="circle")).action is None


def test_garbage_is_ignored(bridge):
    assert send(bridge, b"not json").action is None
    assert send(bridge, b"[1,2]").action is None
    assert send(bridge, gesture(ts="yesterday")).action is None


def test_source_filter_blocks_test_input():
    b = eb.Bridge(eb.Config(actions={"swipe_up": "show"},
                            sources=frozenset({"sen0628"})))
    b.handle("edge/mirror/status", ONLINE, now=SENT_AT, monotonic=0.0)
    assert send(b, gesture(source="synthetic")).action is None
    assert send(b, gesture(id=8, source="sen0628")).action == "show"


@pytest.mark.parametrize("spec", ["", "swipe_up", "swipe_up=reboot", "=show"])
def test_bad_action_config_is_rejected(spec):
    with pytest.raises(ValueError):
        eb.parse_actions(spec)


def test_run_action_refuses_anything_outside_the_whitelist(tmp_path):
    assert eb.run_action("rm -rf /", tmp_path / "never-called.sh") is False


def test_run_action_calls_the_script_with_one_argument(tmp_path):
    log = tmp_path / "calls"
    script = tmp_path / "guest-page.sh"
    script.write_text(f'#!/bin/sh\necho "$#:$1" >> {log}\n')
    script.chmod(0o755)
    assert eb.run_action("show", script) is True
    assert log.read_text() == "1:show\n"
