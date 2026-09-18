# 002 · Display power via HDMI-CEC, not the Wayland compositor

- **Status:** Accepted — supersedes the compositor approach planned for roadmap phase 2
- **Date:** 2026-09-09

## Context

The panel should go dark when nobody is in front of the mirror and wake when someone approaches. The
plan was to switch the HDMI output from the compositor, with `wlopm` (as used by `MMM-Remote-Control`'s
monitor endpoints) or `wlr-randr --output HDMI-A-1 --off`.

Tested under labwc on Raspberry Pi OS Trixie, both tools **disable the output** rather than putting the
panel into standby. labwc then creates a headless replacement output, and re-enabling the real one
failed roughly half of the time with `failed to apply configuration`. Every cycle leaked another
headless output — for a display that switches dozens of times a day, not a usable basis.

## Decision

`scripts/presence.py` sends `cec-ctl --standby` / `--image-view-on` to the monitor (logical address 0)
over HDMI-CEC on `/dev/cec1`. The Pi's output stays configured and enabled throughout; the monitor's
own controller handles standby.

## Alternatives considered

| Option | Why not |
|---|---|
| `wlopm --off '*'` via `MMM-Remote-Control` | Disables the output; headless output leak, unreliable re-enable |
| `wlr-randr --off` directly | Same behavior, same failure |
| Blank page / black overlay in MagicMirror | Backlight stays on — no energy saving, visible glow behind the spy glass |
| `vcgencmd display_power` | Legacy firmware path, not effective under the KMS driver used by Wayland |

## Consequences

- Nothing on the Pi side is reconfigured, so there is nothing to fail on wake: `wlr-randr` reports
  `Enabled: yes` before and after.
- Waking takes 2–3 s — the monitor's own wake-up time, the same as pressing its power button.
- CEC must be enabled in the monitor's OSD, and the user needs to be in the `video` group.
- The Pi 4 exposes one CEC device per HDMI port. Addressing the wrong one fails with errno 64 (`ENONET`)
  and no further hint; the device is configurable via `CEC_DEVICE`.
- The CEC adapter loses its logical address on reboot and occasionally on adapter reset.
  `presence.py` reconfigures and retries once when `cec-ctl` reports "unconfigured".
- When the monitor renegotiates HDMI on wake, the rotation can be lost; `kanshi` reapplies it.
- Presence detection no longer depends on MagicMirror running — `presence.service` has no dependency on
  the MagicMirror unit.
- The time-based part of the original phase 2 (dark at night) moved to [ADR-005](005-power-management.md).
