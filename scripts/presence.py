#!/usr/bin/env python3
"""
presence.py -- switches the mirror panel based on the radar sensor

Reads the digital presence output (OT2) of the Waveshare HMMD mmWave
sensor on GPIO 27 and puts the monitor into standby via HDMI-CEC when
nobody is around.

Wiring:
    sensor 3V3  ->  Pi pin 17  (3.3 V, pin 1 is taken by the fan)
    sensor GND  ->  Pi pin 9   (ground, pin 6 is taken by the fan)
    sensor OT2  ->  Pi pin 13  (GPIO 27)

Why CEC and not the compositor
------------------------------
Under labwc both `wlopm` and `wlr-randr --off` disable the output
rather than putting the panel into standby. The compositor then
creates a headless replacement output, and re-enabling the real one
fails roughly half the time with "failed to apply configuration".
Each cycle leaks another headless output.

CEC sidesteps all of that. The command travels over pin 13 of the HDMI
cable straight to the monitor's own controller, which handles standby
itself. The Pi's output stays configured and enabled throughout --
`wlr-randr` reports `Enabled: yes` before and after. There is nothing
to re-apply, so there is nothing to fail.

Cost: waking the panel takes two to three seconds. That is the
monitor's own wake-up time, the same as pressing its power button.

Note on the device node
-----------------------
The Pi 4 has two HDMI ports and exposes one CEC device per port.
`/dev/cec0` is the first port, `/dev/cec1` the second. Addressing the
wrong one fails with errno=64 (ENONET) and no further explanation.

Requirements:
    sudo apt install python3-gpiozero python3-lgpio v4l-utils
    user must be in the "video" group to open /dev/cec*
"""

import logging
import os
import signal
import subprocess
import sys
import time

from gpiozero import Button

# --- Configuration ---------------------------------------------------

GPIO_PIN = int(os.environ.get("PRESENCE_GPIO", "27"))

# Seconds without detection before the panel is switched off.
GRACE_SECONDS = int(os.environ.get("PRESENCE_GRACE", "120"))

# Input debounce in seconds. Short glitches cause no state change.
BOUNCE_SECONDS = float(os.environ.get("PRESENCE_BOUNCE", "0.5"))

# Minimum gap between two switches. Rapid toggling gives the panel no
# time to settle and produces visible flicker.
MIN_SWITCH_GAP = float(os.environ.get("PRESENCE_MIN_GAP", "5"))

CEC_DEVICE = os.environ.get("CEC_DEVICE", "/dev/cec1")

# Logical CEC address of the monitor. 0 is always the display.
CEC_TARGET = os.environ.get("CEC_TARGET", "0")

# Name the mirror announces on the CEC bus.
CEC_OSD_NAME = os.environ.get("CEC_OSD_NAME", "MagicMirror")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("presence")


# --- CEC -------------------------------------------------------------

def run_cec(args, timeout=15):
    """Run cec-ctl. Returns (ok, combined output)."""
    cmd = ["cec-ctl", "-d", CEC_DEVICE] + args
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        out = (r.stdout or "") + (r.stderr or "")
        return r.returncode == 0, out
    except FileNotFoundError:
        log.error("cec-ctl not found. Install with: sudo apt install v4l-utils")
        sys.exit(1)
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except OSError as e:
        return False, str(e)


def configure_cec():
    """Claim a logical address on the CEC bus.

    Without this cec-ctl refuses to transmit with "Adapter is
    unconfigured". The configuration does not survive a reboot, and it
    can be lost if the adapter resets -- hence the retry in switch()."""
    ok, out = run_cec(["--playback", "--osd-name", CEC_OSD_NAME])
    if ok:
        log.info("CEC adapter configured on %s", CEC_DEVICE)
    else:
        log.warning("Could not configure CEC adapter: %s", out.strip()[:200])
    return ok


def switch(on):
    """Switch the panel. Reconfigures and retries once if the adapter
    has lost its logical address."""
    action = ["--to", CEC_TARGET, "--image-view-on" if on else "--standby"]

    ok, out = run_cec(action)
    if not ok and "unconfigured" in out.lower():
        log.info("CEC adapter lost its address, reconfiguring")
        configure_cec()
        ok, out = run_cec(action)

    if ok:
        log.info("Panel %s", "on" if on else "standby")
    else:
        log.warning("Switching failed: %s", out.strip()[:200])
    return ok


# --- State -----------------------------------------------------------

class Mirror:
    def __init__(self):
        # Unknown at start; the first transition establishes it.
        self.on = None
        self.off_at = None
        self.last_switch = 0.0

    def _too_soon(self):
        return (time.monotonic() - self.last_switch) < MIN_SWITCH_GAP

    def turn_on(self):
        self.off_at = None
        if self.on is True:
            return
        if self._too_soon():
            log.info("Presence detected, waiting out the minimum gap")
            return
        log.info("Presence detected")
        self.last_switch = time.monotonic()
        if switch(True):
            self.on = True

    def schedule_off(self):
        if self.on is False:
            return
        if self.off_at is None:
            self.off_at = time.monotonic() + GRACE_SECONDS
            log.info("Nobody present, switching off in %d s", GRACE_SECONDS)

    def tick(self):
        if self.off_at and time.monotonic() >= self.off_at:
            self.off_at = None
            if self._too_soon():
                # Try again on the next tick.
                self.off_at = time.monotonic() + MIN_SWITCH_GAP
                return
            log.info("Grace period elapsed")
            self.last_switch = time.monotonic()
            if switch(False):
                self.on = False


def main():
    configure_cec()
    mirror = Mirror()

    # pull_up=False: the sensor actively drives the pin to 3.3 V on
    # detection. An internal pull-down holds it low otherwise.
    sensor = Button(GPIO_PIN, pull_up=False, bounce_time=BOUNCE_SECONDS)

    sensor.when_pressed = mirror.turn_on
    sensor.when_released = mirror.schedule_off

    log.info(
        "Started. GPIO %d, grace %d s, min gap %.0f s, CEC %s",
        GPIO_PIN, GRACE_SECONDS, MIN_SWITCH_GAP, CEC_DEVICE,
    )

    # Evaluate the initial state so the panel is not left inverted
    # after a restart.
    if sensor.is_pressed:
        mirror.turn_on()
    else:
        mirror.schedule_off()

    def shutdown(signum, frame):
        log.info("Stopping.")
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    while True:
        mirror.tick()
        time.sleep(1)


if __name__ == "__main__":
    main()