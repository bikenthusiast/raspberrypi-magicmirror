# 005 · Witty Pi 4 Mini for the night, CEC standby during the day

- **Status:** Accepted
- **Date:** 2026-09-07

## Context

A mirror in the hallway is not needed at night. Blanking the panel ([ADR-002](002-display-power-cec.md))
saves the backlight, but the Pi keeps running around the clock. A Raspberry Pi 4B that has shut down
cannot switch itself back on: it has no battery-backed clock and no circuit that restores power at a
given time.

Powering the Pi down also conflicts with presence detection — a Pi that is off detects nobody.

## Decision

A **UUGear Witty Pi 4 Mini** (RTC plus power switch on the GPIO header) cuts power at **22:15** and
restores it at **07:30**. During the day the Pi runs and the radar controls the panel over CEC.

| Time window | Mechanism |
|---|---|
| Day | Pi running, presence detection switches the panel |
| Night | Pi powered off, Witty Pi wakes it in the morning |
| Longer absence | Shutdown by hand, button on the board to wake |

The schedule is versioned as [`config/mirror.wpi.example`](../../config/mirror.wpi.example).

## Alternatives considered

| Option | Why not |
|---|---|
| Display off at night, Pi keeps running | No hardware needed, but 24/7 operation for a device used a few minutes a day |
| systemd timers for display on/off (original phase 2) | Solves only the panel, not the Pi; replaced by this record plus ADR-002 |
| Smart plug | Hard power cut without clean shutdown — risks the SD card |
| Witty Pi 4 (full) | Adds a DC/DC converter up to 30 V and a coin cell instead of a supercap; neither is needed on a fixed 5 V supply |
| Pi 5 with built-in RTC | Replaces working hardware to solve a problem an add-on board solves |

## Consequences

- The PSU plugs into the **Witty Pi's** USB-C, not the Pi's; output is limited to 2.5 A.
- "Default state when powered" must be **ON**, otherwise the mirror stays dark after a power cut until
  someone presses the button behind it.
- Boot takes about 30 s, so the wake time has to be before the first expected use.
- Occupied pins: GPIO 2, 3 (I²C), 4, 17, plus monitoring of GPIO 14 (TXD). 1-Wire must stay off, since
  it claims GPIO 4 and makes the Pi shut down right after every boot.
- Schedule pitfalls, both hit in practice: ON + OFF must add up to 24 h, and a `BEGIN` date in the past
  made the script shut the Pi down immediately on 2026-09-07.
- The journal must be persistent, otherwise every night erases the logs (see
  [`docs/logging.md`](../logging.md)).
