# 007 · Gesture sensor: DFRobot SEN0628 (8×8 time-of-flight) on UART5, no camera

- **Status:** Accepted
- **Date:** 2026-10-12 (sensor chosen 2026-09-29, commissioned 2026-10-07)

## Context

Phase 5 lets a hand gesture show and hide the guest Wi-Fi page. The roadmap planned a USB camera with
MediaPipe for this. Two things changed that plan:

- **Privacy.** The mirror hangs in a hallway and is on all day. A camera in it records everyone who walks
  past, whatever the software does with the frames. The requirement became: no image data at all.
- **Load.** MediaPipe next to Electron on a Pi 4 without an NPU was an open risk in the roadmap.

The Pi sits outside the frame, about a metre from the sensor position. The Witty Pi monitors GPIO 14 (TXD)
to detect shutdown and shares the I²C bus (ADR-004, ADR-005), so neither the primary UART nor I²C over a
metre of cable is a good place for another device.

The detailed comparison of camera-free sensors (APDS-9960, PAJ7620, VL53L5CX/L8CX, MGC3130,
Acconeer A121, Infineon BGT60TR13C) is kept with the project notes; the summary is in the table below.

## Decision

A **DFRobot SEN0628** (ST VL53L7CX time-of-flight sensor with an RP2040, 8×8 zones, 60° × 60°) on
**UART5** (GPIO 12 / 13, pins 32 / 33, `dtoverlay=uart5`, `/dev/ttyAMA5`), powered from 3.3 V.
It runs in **4×4 mode** (~17–25 fps instead of 7 fps at 8×8) and is mounted with the USB-C socket facing
down.

Recognition starts rule-based on the Pi (`scripts/gesture.py`). It is the baseline for a trained model in
pi-edge-ai, which reaches the mirror through the edge bridge (ADR-008).

## Alternatives considered

| Option | Why not |
|---|---|
| USB camera + MediaPipe (original plan) | Records images of everyone in the hallway; CPU competition with Electron |
| APDS-9960, PAJ7620 (IR gesture chips) | Range a few cm up to ~15 cm — a hand in front of a wall mirror is further away |
| MGC3130 (electric field) | ~15 cm range, and the metal mirror coating and panel chassis distort the field |
| VL53L5CX / VL53L8CX breakout on I²C | Same principle, but I²C over ~1 m and shared with the Witty Pi |
| Acconeer A121 (60 GHz, 1 channel) | Measures along the line of sight only: tap in/out, no left/right |
| Infineon BGT60TR13C (60 GHz FMCW, 3 Rx) | Real direction and angle, but €110–230, long lead times, signal processing from scratch. Kept as phase 5b |
| SEN0628 over USB-C | Streams 8×8 only (7 fps). DFRobot's Python library hard-codes `/dev/ttyAMA0` = GPIO 14/15, which the Witty Pi monitors |
| SEN0628 on the primary UART (GPIO 14/15) | GPIO 14 must stay untouched for the Witty Pi (ADR-004) |

## Consequences

- No image data anywhere: the sensor delivers 16 or 64 distances per frame. A person is not recognisable
  in it.
- No compute risk: a frame is 32 bytes; the detector costs nothing measurable next to Electron.
- The protocol needs care: bytes must be sent one by one, the first command after power-up can be lost,
  and a mode switch needs 5 s. `scripts/sen0628.py` handles this. The sensor can hang after a reboot
  without power loss and only recovers after a full power cut — the service has to tolerate a sensor
  that does not answer.
- **3.3 V only.** The data lines follow the supply; at 5 V they carry 5 V into the Pi's GPIOs.
- Range is the limit: at 60–80 cm a 4×4 zone is ~20 cm wide and a hand fills half of one. The rule
  recognises swipes reliably up close but only about one in five at the target distance
  (docs/sen0628.md). Closing that gap is the job of the trained model; if it cannot, the radar
  (phase 5b) is the fallback.
- The sensor needs an **open cut-out** in the frame. The mirror coating reflects the 940 nm laser, so it
  cannot sit behind the glass.
- One reader only: `gesture.service` and pi-edge-ai's sensor reader must not run at the same time on
  `/dev/ttyAMA5`.
