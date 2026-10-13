# 010 · A health-check script with alerts on change, not a monitoring stack

- **Status:** Proposed
- **Date:** 2026-10-13

## Context

On 13 October 2026 the mirror froze around 14:37: Wi-Fi gone, MagicMirror stopped, mouse dead, a
desktop warning about under-voltage. Nobody noticed until someone walked past. The persistent journal
ended in normal operation; nothing written after the freeze reached the SD card, so the cause could
not be proven afterwards. `vcgencmd get_throttled` was `0x0` after the power cycle.

Two gaps showed: problems are only noticed by looking at the wall, and the values that would explain a
freeze (voltage flags, temperature, free memory) were not recorded anywhere. The Pi runs from 07:30 to
22:15 (ADR-005), has 8 GB RAM and an SD card, and already has MMM-Remote-Control for the mirror's own
notifications (ADR-001). Deployment is pulled by the Pi (ADR-009).

## Decision

A shell script, `scripts/health-check.sh`, runs once a minute from a systemd user timer. It writes one
line of measurements to the journal and checks six conditions: power, temperature, memory, disk,
MagicMirror, internet. A check that goes bad, or recovers, raises an alert on the mirror (alert module
via MMM-Remote-Control) and on the phone (ntfy push, topic in `secrets.js`). It restarts MagicMirror
when systemd has given up on it. The hardware watchdog covers a frozen system.

## Alternatives considered

| Option | Why not |
|---|---|
| Prometheus + node_exporter + Grafana (+ Alertmanager) | Three to four services and a time-series database for one device; RAM and constant SD writes on the Pi itself, or a second machine that is not always on. The dashboard answers questions nobody asks daily |
| Hosted monitoring (Grafana Cloud, Healthchecks.io, UptimeRobot) | An account and an outbound agent or ping for a home device; the useful part, the Pi's own voltage and temperature flags, still needs a local script |
| Cron job appending to a file | What was used for the first day. No alerts, no rotation, not versioned, not reinstalled after a fresh setup |
| `monit` | Covers the checks, but a second configuration language and its own alert transport (mail) for six checks that fit in one script |
| Alert every minute while a check is bad | Noise: a dead Wi-Fi for an hour would send sixty messages. Alerts on change, with the duration in the recovery message, carry the same information |

## Consequences

- Problems reach the phone within one to three minutes, also when nobody is in the hallway.
- The journal holds a minute-by-minute record; `journalctl -t health -b -1` shows the minutes before a
  freeze, as far as they reached the disk.
- An ntfy topic is a shared secret by name only. It lives in `secrets.js` (ADR-006); anyone who learns it
  can read the alerts.
- Phone alerts cannot leave while the internet is down. The mirror shows that case, and the recovery
  message reports the outage afterwards.
- Stopping MagicMirror by hand raises a `magicmirror` alert after three minutes. Stop the timer as well
  for longer maintenance.
- Thresholds are guesses from one incident and the Pi 4's limits. They are environment variables, so
  tuning them needs no code change.
- The watchdog is system configuration outside the repository; `deploy.sh` does not apply it.
