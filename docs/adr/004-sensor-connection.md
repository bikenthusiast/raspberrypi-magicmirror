# 004 · Radar on a GPIO input, UART not connected in operation

- **Status:** Accepted
- **Date:** 2026-09-04

## Context

The Pi is mounted externally below the mirror; the sensor sits in the frame, at least a meter away. The
HMMD offers two interfaces: a UART stream with distances and zone data, and a digital presence output
(`OT2`, high on presence).

The Witty Pi from [ADR-005](005-power-management.md) monitors the voltage on **GPIO 14 (TXD)** to detect
that the system has shut down; connected devices must not influence that line. GPIO 17 is taken by the
Witty Pi's SYS_UP signal, and pins 1 and 6 by the case fan.

Three variants were considered in the roadmap:

| Variant | Effort | Assessment |
|---|---|---|
| **A** — sensor directly on GPIO, `OUT` only | low | sufficient for on/off |
| **B** — sensor directly on GPIO, UART | low | a fast serial link over an unshielded meter is fragile, and TXD is off-limits |
| **C** — ESP32 at the mirror, reports over Wi-Fi | +1 evening, +6 € | clean, but a second node to maintain |

## Decision

**Variant A.** Three wires: 3V3 → pin 17, GND → pin 9, `OT2` → pin 13 (GPIO 27). The UART is not
connected in operation. Zones and range are configured once from the development machine through a
USB-TTL adapter (FT232); the sensor keeps the settings.

`scripts/presence.py` reads GPIO 27 with `gpiozero` on the `lgpio` pin factory and runs as the systemd
service `presence.service`.

## Consequences

- On/off is all the mirror needs, and a digital level is robust over the cable length.
- No live distance data and no runtime reconfiguration from the Pi. Retuning zones means connecting the
  adapter again.
- Debounce (0.5 s), a grace period before switching off (120 s) and a minimum gap between switches
  (5 s) are handled in software and configurable through environment variables in the unit.
- Fan and radar share the Pi's 3.3 V rail. If the sensor misbehaves, supply is the first suspect; the fan
  could move to 5 V (pin 4).
- An ESP32 node (variant C) remains possible for phase 5, if more sensors end up at the mirror.
