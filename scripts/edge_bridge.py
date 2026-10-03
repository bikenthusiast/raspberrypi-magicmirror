#!/usr/bin/env python3
"""
edge_bridge.py -- turns pi-edge-ai gesture events into mirror actions

Subscribes to the MQTT topics published by the sister project pi-edge-ai
and maps recognised gestures to the hidden-page trigger from ADR-001:

    edge/<device>/gesture  {"gesture":"swipe_up", ...}
        -> GESTURE_ACTIONS "swipe_up=show"
        -> scripts/guest-page.sh show
        -> MMM-pages SHOW_HIDDEN_PAGE "gast" -> MMM-GuestWifi

The contract (topics, schema v1, rules for consumers) is defined in
pi-edge-ai, docs/mqtt.md. tests/fixtures/gesture_v1.json is an exact copy
of the producer's example payload; the bridge is tested against it.

Why a Python service and not a MagicMirror module
-------------------------------------------------
See docs/adr/008-edge-event-bridge.md. In short: no new JavaScript
dependency (an MQTT client in node_modules is exactly the kind of
loosely-pinned dependency MMM-GuestWifi avoided), the same shape as
presence.py, and one trigger mechanism for radar, gestures and the shell.

What gets dropped, and why
--------------------------
Every message passes these checks, in this order. Each rejection is
logged with its reason, because "the gesture did nothing" is otherwise
impossible to debug from the couch.

    unknown schema version   the contract says: ignore, never guess
    producer offline         status is retained; act only while online
    stale (> BRIDGE_MAX_AGE) QoS 1 redelivers after a reconnect -- a
                             swipe from five minutes ago must not open
                             the guest page now
    duplicate id             same reason, second line of defence
    source not allowed       BRIDGE_SOURCES=sen0628 blocks test input
                             (synthetic, replay) in daily use
    unmapped gesture         new gesture names are allowed by the
                             contract; they simply do nothing here
    too soon (< BRIDGE_MIN_GAP) the same action twice in a row, even if
                             the producer's cooldown is set too short.
                             show followed by hide is always allowed

Security: the action is looked up in a fixed whitelist (show, hide) and
passed to guest-page.sh as a single argument. Nothing from the message
ever reaches a shell. MQTT credentials come from the environment
(systemd EnvironmentFile, not in the repo); the broker ACL gives the
user "mirror" read access only.

Configuration (environment):
    MQTT_HOST        default localhost
    MQTT_PORT        default 1884 (the authenticated listener)
    MQTT_USERNAME    default mirror
    MQTT_PASSWORD    required on port 1884
    EDGE_PREFIX      default edge
    GESTURE_ACTIONS  default "swipe_up=show,swipe_down=hide"
    BRIDGE_MAX_AGE   seconds, default 5
    BRIDGE_MIN_GAP   seconds, default 2
    BRIDGE_SOURCES   comma-separated, empty = accept all (default)
    GUEST_PAGE_SCRIPT default: guest-page.sh next to this file

Requirements:
    sudo apt install python3-paho-mqtt
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

SCHEMA_VERSION = 1
ALLOWED_ACTIONS = ("show", "hide")

log = logging.getLogger("edge-bridge")


# --- Configuration ---------------------------------------------------

def parse_actions(spec: str) -> dict[str, str]:
    """'swipe_up=show,swipe_down=hide' -> {'swipe_up': 'show', ...}"""
    actions: dict[str, str] = {}
    for item in filter(None, (part.strip() for part in spec.split(","))):
        gesture, sep, action = item.partition("=")
        gesture, action = gesture.strip(), action.strip()
        if not sep or not gesture:
            raise ValueError(f"GESTURE_ACTIONS: expected gesture=action, got {item!r}")
        if action not in ALLOWED_ACTIONS:
            raise ValueError(f"GESTURE_ACTIONS: action {action!r} not in {ALLOWED_ACTIONS}")
        actions[gesture] = action
    if not actions:
        raise ValueError("GESTURE_ACTIONS is empty -- the bridge would do nothing")
    return actions


@dataclass
class Config:
    actions: dict[str, str]
    prefix: str = "edge"
    max_age_s: float = 5.0
    min_gap_s: float = 2.0
    sources: frozenset[str] = frozenset()   # empty: accept every source

    @classmethod
    def from_env(cls, env=os.environ) -> Config:
        sources = env.get("BRIDGE_SOURCES", "")
        return cls(
            actions=parse_actions(env.get("GESTURE_ACTIONS",
                                          "swipe_up=show,swipe_down=hide")),
            prefix=env.get("EDGE_PREFIX", "edge"),
            max_age_s=float(env.get("BRIDGE_MAX_AGE", "5")),
            min_gap_s=float(env.get("BRIDGE_MIN_GAP", "2")),
            sources=frozenset(s.strip() for s in sources.split(",") if s.strip()),
        )


# --- Decision logic (pure, tested without a broker) -------------------

@dataclass
class Decision:
    action: str | None
    reason: str


@dataclass
class Bridge:
    config: Config
    online: dict[str, bool] = field(default_factory=dict)
    seen: deque = field(default_factory=lambda: deque(maxlen=256))
    last_action_at: dict[str, float] = field(default_factory=dict)

    def handle(self, topic: str, payload: bytes, *, now: datetime,
               monotonic: float) -> Decision:
        parts = topic.split("/")
        if len(parts) != 3 or parts[0] != self.config.prefix:
            return Decision(None, f"foreign topic {topic}")
        _, device, kind = parts

        try:
            msg = json.loads(payload)
        except (ValueError, UnicodeDecodeError):
            return Decision(None, "payload is not JSON")
        if not isinstance(msg, dict) or msg.get("v") != SCHEMA_VERSION:
            return Decision(None, f"unknown schema version {msg.get('v') if isinstance(msg, dict) else None!r}")

        if kind == "status":
            self.online[device] = bool(msg.get("online"))
            state = "online" if self.online[device] else "offline"
            return Decision(None, f"status: {device} {state}")
        if kind != "gesture":
            return Decision(None, f"not a gesture ({kind})")

        if not self.online.get(device, False):
            return Decision(None, f"{device} is not online")

        try:
            ts = datetime.fromisoformat(msg["ts"])
        except (KeyError, TypeError, ValueError):
            return Decision(None, "missing or invalid ts")
        age = (now - ts).total_seconds()
        if abs(age) > self.config.max_age_s:
            return Decision(None, f"stale ({age:.1f} s old)")

        key = (device, msg.get("id"))
        if key in self.seen:
            return Decision(None, f"duplicate id {msg.get('id')}")
        self.seen.append(key)

        source = msg.get("source")
        if self.config.sources and source not in self.config.sources:
            return Decision(None, f"source {source!r} not allowed")

        gesture = msg.get("gesture")
        action = self.config.actions.get(gesture)
        if action is None:
            return Decision(None, f"gesture {gesture!r} not mapped")

        previous = self.last_action_at.get(action, float("-inf"))
        if monotonic - previous < self.config.min_gap_s:
            return Decision(None, f"too soon after the last {action}")
        self.last_action_at[action] = monotonic
        return Decision(action, f"{gesture} from {device}/{source}")


# --- Side effects ----------------------------------------------------

def run_action(action: str, script: Path) -> bool:
    """Call guest-page.sh. Only whitelisted words ever get here."""
    if action not in ALLOWED_ACTIONS:      # defence in depth
        log.error("refusing unknown action %r", action)
        return False
    try:
        r = subprocess.run([str(script), action], capture_output=True,
                           text=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        log.error("guest-page.sh %s failed: %s", action, exc)
        return False
    if r.returncode != 0:
        log.error("guest-page.sh %s exited %d: %s", action, r.returncode,
                  (r.stderr or r.stdout).strip()[:200])
        return False
    log.info("guest page %s", action)
    return True


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s  %(levelname)-7s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    try:
        config = Config.from_env()
    except ValueError as exc:
        log.error("%s", exc)
        return 1

    script = Path(os.environ.get(
        "GUEST_PAGE_SCRIPT", Path(__file__).resolve().parent / "guest-page.sh"))
    if not os.access(script, os.X_OK):
        log.error("%s is missing or not executable", script)
        return 1

    try:
        import paho.mqtt.client as mqtt
    except ImportError:
        log.error("paho-mqtt missing. Install with: sudo apt install python3-paho-mqtt")
        return 1

    host = os.environ.get("MQTT_HOST", "localhost")
    port = int(os.environ.get("MQTT_PORT", "1884"))
    bridge = Bridge(config)
    topics = [(f"{config.prefix}/+/gesture", 1), (f"{config.prefix}/+/status", 1)]

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                         client_id="magicmirror-edge-bridge")
    user = os.environ.get("MQTT_USERNAME", "mirror")
    password = os.environ.get("MQTT_PASSWORD")
    if password:
        client.username_pw_set(user, password)

    def on_connect(c, _userdata, _flags, reason_code, _props=None):
        if getattr(reason_code, "is_failure", False):
            log.error("MQTT connect refused: %s", reason_code)
            return
        # Subscribe on every (re)connect; retained status arrives right away.
        c.subscribe(topics)
        log.info("connected to %s:%d, listening on %s", host, port,
                 ", ".join(t for t, _ in topics))

    def on_message(_c, _userdata, message):
        decision = bridge.handle(message.topic, message.payload,
                                 now=datetime.now(UTC),
                                 monotonic=time.monotonic())
        if decision.action:
            log.info("%s -> %s", decision.reason, decision.action)
            # Runs on paho's network thread. guest-page.sh is one local
            # HTTP call; blocking for it is simpler than a worker queue.
            run_action(decision.action, script)
        elif decision.reason.startswith("status:"):
            log.info("%s", decision.reason)
        else:
            log.info("ignored: %s", decision.reason)

    client.on_connect = on_connect
    client.on_message = on_message
    log.info("actions: %s, sources: %s", config.actions,
             ", ".join(sorted(config.sources)) or "all")
    client.connect_async(host, port, keepalive=30)
    try:
        client.loop_forever(retry_first_connection=True)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
