# 003 · 24 GHz mmWave radar (Waveshare HMMD) for presence detection

- **Status:** Accepted
- **Date:** 2026-08-24 (ordered in CW 35)

## Context

The display should stay on while someone uses the mirror and switch off after they leave. Using a
mirror typically means standing still: shaving, brushing teeth, fixing hair. The sensor sits in a
hallway, so people walking past at a distance should not wake the mirror.

Constraints from the build: the sensor has to sit in the frame, and both the metal-coated spy glass and
the LCD chassis block radio waves.

## Decision

A **Waveshare HMMD mmWave sensor** (S3KM1110, 24 GHz FMCW), placed in a pocket in the bottom frame rail
outside the glass area.

## Alternatives considered

| Option | Why not |
|---|---|
| PIR (HC-SR501) | Detects motion only. Someone standing still in front of the mirror "disappears" and the display turns off mid-use |
| Ultrasonic (HC-SR04) | Measures distance, not presence of a person; prone to interference |
| Camera + person detection | Works, but costs CPU on a Pi that already renders Electron full screen; overkill for on/off. A camera comes in phase 5 anyway |
| BLE presence (phone) | Detects devices, not people — wrong semantics for a mirror guests use too |
| HLK-LD2410C | Common and cheap, but the HMMD allows **sensitivity per distance zone** (near zone sensitive, far zones damped against hallway traffic) and ships Raspberry Pi examples |

## Consequences

- Detects stationary people, down to breathing movement.
- Wood and MDF are largely transparent at 24 GHz, so a pocket with 1–2 mm of remaining wood works; the
  frame must not be closed before the sensor position is final.
- Zone sensitivity is only meaningful at the final installation location and has to be tuned there.
- Runs on 3.3 V only — 5 V destroys the module.
- How the sensor is wired to the Pi is decided separately in [ADR-004](004-sensor-connection.md).
