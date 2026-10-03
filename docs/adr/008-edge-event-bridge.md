# 008 · Gesture events from pi-edge-ai reach the mirror through a Python bridge service

- **Status:** Proposed
- **Date:** 2026-10-03

## Context

Phase 5 lets a hand gesture open the guest Wi-Fi page. The gesture sensor (DFRobot SEN0628, 8×8
time-of-flight, no camera) delivers raw depth frames only; the classification runs in the sister
project [pi-edge-ai](https://github.com/bikenthusiast/pi-edge-ai), which publishes each recognised
gesture on MQTT — topic `edge/<device>/gesture`, schema v1, defined in pi-edge-ai's `docs/mqtt.md`
and its ADR 0004. The broker (Mosquitto) runs on the same Pi.

The mirror side has to subscribe, decide whether a message should do anything, and trigger the hidden
page. ADR-001 already defines that trigger: `SHOW_HIDDEN_PAGE` / `LEAVE_HIDDEN_PAGE` through
MMM-Remote-Control, wrapped by `scripts/guest-page.sh`.

## Decision

A small Python service, [`scripts/edge_bridge.py`](../../scripts/edge_bridge.py) with
[`systemd/edge-bridge.service`](../../systemd/edge-bridge.service), subscribes to `edge/+/gesture` and
`edge/+/status` as the read-only MQTT user `mirror`, maps gestures to `show` / `hide` via
`GESTURE_ACTIONS`, and calls `guest-page.sh`. It drops a message unless the producer is online, the
message is fresh (≤ 5 s), its id is new, its source is allowed and the same action did not just run.

## Alternatives considered

| Option | Why not |
|---|---|
| MagicMirror module with an MQTT client in `node_helper` (the `MMM-EdgeEvents` sketched in pi-edge-ai's README) | Adds an npm dependency with its own release cycle — the class of problem MMM-GuestWifi was built to avoid. Worth it only once the mirror should *display* edge data, not just react to it |
| Classifier and sensor reader directly in this repo, like `presence.py` | Couples the classification to the mirror and duplicates event log, publisher and tests that exist in pi-edge-ai (its ADR 0004) |
| Producer calls `guest-page.sh` itself | pi-edge-ai would need the Remote-Control API key and knowledge of mirror pages; the contract would be a shell script instead of a versioned message |
| Generic MQTT → notification bridge (e.g. an existing MMM-MQTT module) | Forwards everything; none of the freshness, duplicate and online checks a gesture needs |

## Consequences

- Still one trigger mechanism: radar, gesture and shell all end in `guest-page.sh` (ADR-001).
- The bridge is testable without a broker: the decision logic is a pure function, tested in
  `tests/test_edge_bridge.py` against `tests/fixtures/gesture_v1.json` — an exact copy of the
  producer's contract example. Changing the contract means changing both copies.
- The whole chain can be tested before the sensor is wired: `make gesture-sim` in pi-edge-ai publishes
  synthetic swipes. `BRIDGE_SOURCES=sen0628` blocks such test input in daily use.
- Needs the authenticated listener on port 1884 with the `mirror` user and ACL from pi-edge-ai's
  `docs/mqtt.md`. Credentials live in `/etc/magicmirror/edge-bridge.env`, outside the repo (ADR-006).
- The bridge acts on the producer's timestamp. As long as both run on the same Pi there is no clock
  skew; on two devices, both need NTP or `BRIDGE_MAX_AGE` drops everything.
- `MMM-SpotifyPages` still closes the hidden page after `hiddenPageTimeoutMs`; a swipe down closes it
  earlier.
