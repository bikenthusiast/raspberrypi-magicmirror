# Hardware

Structure, components, and pin assignment of the mirror.

> [!NOTE]
> The preparation steps below are complete; they are kept as the reference for a rebuild.

---

## Preparing the Pi

### Commands to run

```bash
sudo raspi-config nonint do_i2c 0          # enable I2C
sudo raspi-config nonint do_serial_hw 0    # enable hardware UART
sudo raspi-config nonint do_serial_cons 1  # disable serial login shell
```

Then add to `/boot/firmware/config.txt`:

```
dtoverlay=disable-bt
enable_uart=1
```

`disable-bt` moves the stable PL011 UART from Bluetooth onto GPIO 14/15.
Without it, that pin pair carries the mini-UART instead, whose baud rate
tracks the core clock and drifts under dynamic clocking — producing sporadic
garbage data that is hard to distinguish from a wiring fault. Cost: no more
Bluetooth, irrelevant for the mirror.

Then reboot.

### Verification after reboot

```bash
ls -l /dev/serial*                 # serial0 -> ttyAMA0 expected
sudo raspi-config nonint get_i2c   # 0 = enabled
i2cdetect -y 1                     # empty as long as no Witty Pi is attached
grep -n "w1-gpio" /boot/firmware/config.txt   # must stay empty
```

`i2cdetect` later shows `08` once the Witty Pi is attached.

### 1-Wire must stay disabled

1-Wire uses GPIO 4 by default — exactly the pin the Witty Pi uses to receive
its shutdown signal. With 1-Wire active, the Pi shuts back down immediately
after every boot.

**Status:** currently inactive, `grep` finds no entry. When adding future
sensors, make sure 1-Wire isn't accidentally enabled. If it's needed, move it
to a different pin:

```
dtoverlay=w1-gpio,gpiopin=18
```

---

## Components

| Component | Model | Purpose | Status |
|---|---|---|---|
| Computer | Raspberry Pi 4B Rev 1.4, 8 GB | MagicMirror, sensor processing | in use |
| PSU | Official Raspberry Pi USB-C, 5.1 V / 3.0 A | Powers the Witty Pi | installed (feeds the Witty Pi) |
| Power management | UUGear Witty Pi 4 Mini | RTC, scheduled power on/off | installed |
| Stacking header | 2×20 GPIO, UUGear | Extends the pins past the Witty Pi | installed |
| Standoffs | M2.5, 10 and 12 mm, plastic | Mounting clearance with stacking header | installed (length chosen after measuring) |
| Presence sensor | Waveshare HMMD mmWave (S3KM1110) | Presence detection | installed, OT2 on GPIO 27 |
| Display | MSI PRO MP273QW E14, 27″ 16:9, 2560×1440, portrait | Display | in use |
| Spy mirror glass | VSG laminated safety glass, 6 mm, 12 % transmission, 614 × 366 mm | Mirror surface | specified |
| Fan | 2-wire, on pin 1 and 6 | Cooling | installed |
| USB-TTL adapter | Waveshare FT232, USB-C | Radar sensor configuration | available |
| Camera | USB webcam 1080p | Gesture recognition, phase 5 | open |

> [!NOTE]
> Glass and frame specifications: see drawing SM-001.

### Why this selection

**Witty Pi 4 Mini instead of Witty Pi 4:** The full variant differs by adding
a DC/DC converter for input voltages up to 30 V and a CR2032 coin cell instead
of a supercapacitor. Neither is needed with a fixed 5 V supply. The capacitor
holds the time for about 17 hours without power — and even if it's lost, the
Pi recovers it via NTP on the next boot. See [ADR-005](adr/005-power-management.md).

**HMMD instead of LD2410C:** Sensitivity can be configured independently per
distance zone. The near zone in front of the mirror can stay sensitive while
farther zones are dampened — otherwise every pass through the hallway would
wake the mirror.

**mmWave instead of PIR:** A PIR sensor reacts only to motion. Someone
shaving or brushing their teeth in front of the mirror doesn't move enough for
that — the display would turn off mid-use. mmWave measures reflections and
picks up even breathing motion. See [ADR-003](adr/003-presence-sensor.md).

---

## GPIO assignment

State: all components mounted.

| Pi pin | Signal | Used by | Purpose |
|---|---|---|---|
| 1 | 3V3 | **Fan** | Power |
| 3 | GPIO 2 (SDA1) | Witty Pi | I2C to MCU |
| 5 | GPIO 3 (SCL1) | Witty Pi | I2C to MCU |
| 6 | GND | **Fan** | Ground |
| 7 | GPIO 4 | Witty Pi | Button / shutdown signal |
| 8 | GPIO 14 (TXD) | Witty Pi | Monitoring only, detects system shutdown |
| 9 | GND | **Radar** | Ground |
| 11 | GPIO 17 | Witty Pi | SYS_UP signal |
| 13 | GPIO 27 | **Radar** | Presence digital (OT2) |
| 17 | 3V3 | **Radar** | Power |

All remaining pins are free.

### Why radar isn't on pin 1 and 6

The fan already occupies pin 1 (3V3) and pin 6 (GND). Both signals appear
multiple times on the header, so the radar sensor uses different ones:

| Sensor | Pin | instead of |
|---|---|---|
| 3V3 | **17** | 1 |
| GND | **9** | 6 |
| OT2 | 13 | unchanged |

Electrically identical, just physically elsewhere. 3.3 V is present on pins 1
and 17, ground on pins 6, 9, 14, 20, 25, 30, 34, and 39.

> [!NOTE]
> The Pi's 3.3 V rail has a lower current capacity than the 5 V rail —
> typically a few hundred milliamps total for all loads combined. The fan and
> radar sensor share it. If the sensor later drops out or behaves oddly, the
> power supply is the first suspect. The fan could then be moved to pin 4
> (5 V), relieving the 3.3 V rail — though it would run faster and louder
> there.

### GPIO 27 instead of GPIO 17

GPIO 27 was deliberately chosen for the presence output instead of the more
obvious GPIO 17: the latter is used by the Witty Pi for the SYS_UP signal.

> [!CAUTION]
> **The official fan for the Raspberry Pi 4 case uses pin 8 (GPIO 14) for PWM
> control.** This pin is monitored by the Witty Pi to detect shutdown. A PWM
> signal there interferes with that detection — in the worst case the Witty Pi
> cuts power during operation.
>
> The fan currently installed is wired to pin 1 and 6, so it has no control
> line and is not a concern. If switched to a PWM fan, its control line must
> go on a free GPIO, never GPIO 14.
>
> The Pi 4B has **no** 4-pin JST fan connector — that was introduced with the
> Pi 5.

### Radar sensor wiring

> [!WARNING]
> **3.3 V, not 5 V.** The HMMD operates entirely on 3.3 V. Powering it from
> pin 2 (5 V) destroys the module.

| Sensor | Pi pin | GPIO | Function |
|---|---|---|---|
| 3V3 | **17** | — | 3.3 V (pin 1 is used by the fan) |
| GND | **9** | — | Ground (pin 6 is used by the fan) |
| OT2 | **13** | GPIO 27 | Presence high/low |
| TX | — | ~~GPIO 15 (RXD)~~ | not needed, see below |
| RX | — | ~~GPIO 14 (TXD)~~ | **do not connect** |

Three wires are enough for operation. The UART connection is only needed for
configuration and runs through the FT232 adapter on the development machine.

Both sides use 3.3 V logic — no level shifter needed.

### Why TXD stays unconnected

The Witty Pi doesn't use GPIO 14 itself but monitors its voltage: TXD is HIGH
while the system is running and goes LOW after shutdown. That's how the board
knows when it's safe to cut power. Per the manual, connected devices must not
alter this behavior, or the Pi stays powered indefinitely.

For that reason, only the receive direction is wired. This means the sensor
can't be configured from the Pi — sensitivity zones and range are set once via
a USB-TTL adapter on the development machine.

> [!NOTE]
> The HMMD exposes the digital presence output OT2 on J2 pin 5, high on
> presence (verified). The sensor runs at 115200 8N1, firmware v1.6.1.

---

## Mounting the Witty Pi

The board is **not** plugged directly onto the GPIO header but through a 2×20
stacking header. Only that keeps the radar sensor's pins reachable.

Per the manual, feed the stacking header's long pins through the holes on the
back, then place a steel ruler between the two pin rows and use it to press
the board down evenly until it seats against the plastic.

**Included are M2.5×10 screws and 4 mm spacers** — with a stacking header
these are no longer long enough. The board spacing comes from the height of
the header plastic (8.5 mm) plus the socket strip on the underside of the
Witty Pi. Measure with calipers after delivery and use the matching standoff
length.

### Power supply

> [!IMPORTANT]
> The PSU plugs into the **Witty Pi's USB-C port**, not the Pi's. Only that
> way can the board cut power. If the Pi is powered directly, the hard cutoff
> is ineffective.

The Witty Pi's output is rated up to 2.5 A — that's the limiting figure, not
the PSU's 3.0 A. Sufficient for a Pi 4B plus webcam.

### Setting that must not stay at default

| Setting | Default | For the mirror |
|---|---|---|
| Default state when powered | OFF | **ON** |

At `OFF`, the Pi doesn't start on its own once power is applied — it waits for
a button press. After a power outage, the mirror would stay dark until
someone reaches behind the unit. Change this in `wittyPi.sh` under item 11
(*View/change other settings*).

### Software

> [!NOTE]
> The UUGear installer ran fine on Raspberry Pi OS Trixie (Debian 13):
>
> ```bash
> wget https://www.uugear.com/repo/WittyPi4/install.sh
> sudo sh install.sh
> ```

The button on the board remains the fallback: it cleanly shuts the Pi down and
back up. If a schedule powers it off at the wrong time, this provides access
again without disassembly — one more argument for the accessible external
mounting.

---

## Display control

The panel is put into standby and woken over HDMI-CEC by `scripts/presence.py`
using `cec-ctl` on `/dev/cec1`. The Pi 4 exposes one CEC device per HDMI port
(cec0 = first port, cec1 = second); using the wrong one fails with
`errno=64 ENONET`. CEC target 0 is always the display. The user running the
script must be in the `video` group.

**Why not the compositor:** under labwc, both `wlopm` and `wlr-randr --off`
disable the output entirely instead of putting the panel into standby. The
compositor then creates a headless replacement output, and re-enabling the
real one failed roughly half the time with "failed to apply configuration,"
leaking a headless output on every cycle. With CEC, the Pi's own output stays
enabled the whole time.

**Cost:** waking takes 2–3 s (the monitor's own wake-up time).

Rotation is handled by `kanshi` (profile in `config/desktop/kanshi.conf`),
which reapplies the transform after Electron starts and again after the
monitor renegotiates HDMI on wake.

Decision record: [ADR-002](adr/002-display-power-cec.md).

---

## Frame construction

The Pi is mounted **externally, below the mirror**, not behind it. Reasons:
accessibility for the SD card, button, and future add-ons; no added heat
buildup in an enclosed box; a thinner overall mirror.

### Layer stack, front to back

| Layer | Note |
|---|---|
| Spy mirror glass | Metal-coated, blocks RF |
| Black bezel | Hides the inactive panel edge |
| LCD panel | Metal chassis, blocks RF completely |
| Air gap | Cabling, ventilation |
| Back panel | MDF, presses the stack against the rabbet |

There must be **no gap** between the spy mirror glass and the panel — even a
millimeter creates a visible double reflection. Pressure comes from behind via
the back panel, with a strip of foam rubber in between.

### Dimensions 27″ 16:9

| Size | Value |
|---|---|
| Active area, landscape | 59.8 × 33.6 cm |
| Active area, portrait | 33.6 × 59.8 cm |
| Diagonal | 68.6 cm |
| Resolution | 2560 × 1440 (landscape) / 1440 × 2560 (portrait) |

These are panel dimensions without the frame. Measure on the actual device.

### Radar sensor mounting location

The spy mirror glass is metal-coated and attenuates RF, and the LCD chassis
blocks it entirely. The sensor therefore has to sit **outside the panel area
and outside the metal-coated glass area**.

Practical option: a pocket in the bottom frame rail with one to two
millimeters of remaining wood. Wood and MDF are largely transparent to mmWave.

The frame should therefore not be permanently closed up before the sensor
position is finalized.

---

## Open items

| Item | Status |
|---|---|
| I2C enabled | **done** |
| Hardware UART, `/dev/serial0` present | **done** |
| Digital output on HMMD present? | **done** — OT2 on J2 pin 5, high on presence |
| Sensor connection: GPIO or ESP32 | **decided** — direct on GPIO, variant A, see [ADR-004](adr/004-sensor-connection.md) |
| Sensor commissioned | **done** — 115200 8N1, firmware v1.6.1 |
| Serial login shell disabled | verify with `raspi-config nonint get_serial_cons` |
| Standoff length | done — measured during mounting |
| Witty Pi software under Trixie | done — installed, board mounted, schedule active |
| Fan reconnected after mounting | done |
| Display control under Wayland/labwc | done — replaced by HDMI-CEC, see ADR-002 |
| Adjust sensitivity zones | only meaningful at the installation location |
| CPU headroom for gesture recognition | open, measure before phase 5 |
