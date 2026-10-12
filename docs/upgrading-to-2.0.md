# Upgrading from 1.0 to 2.0

Steps for a mirror that runs **v1.0**. Every block can be checked before moving to the next one. What
changed and why: [CHANGELOG.md](../CHANGELOG.md).

Steps 1–4 are needed for every 2.0 installation. Steps 5–7 depend on what the mirror has: the gesture
sensor, pi-edge-ai, automatic deployment.

| Step | Needed for | Takes |
|---|---|---|
| 1 Prepare | all | 5 min |
| 2 Update the repository | all | 5 min |
| 3 Presence service: CEC port | all | 5 min |
| 4 Calendar module from the fork | all | 5 min |
| 5 Gesture sensor | SEN0628 attached | 30 min + wiring |
| 6 Edge bridge | pi-edge-ai on this Pi | 15 min |
| 7 Automatic deployment | CI/CD wanted | 15 min |

---

## 1 · Prepare

```bash
cd ~/Projects/raspberrypi-magicmirror
git status                                  # note any local changes
git rev-parse HEAD > ~/mirror-before-2.0    # commit to return to
cp config/secrets.js ~/secrets.js.bak       # never in git, so back it up
```

Local changes to tracked files have to go first: commit them via a branch, or `git stash`. From 2.0 on,
the Pi is a deploy target and is not edited in place ([ADR-009](adr/009-pull-based-deployment.md)).

## 2 · Update the repository

```bash
git fetch --tags origin
git switch main
git pull --ff-only
git describe --tags                         # v2.0.0
```

If `git pull` stops with *untracked working tree files would be overwritten*, files with the same names
were copied onto the Pi by hand (typically `scripts/gesture.py` and `scripts/tof_*.py`). Move them aside
and pull again:

```bash
mkdir -p ~/pre-2.0 && mv <files from the message> ~/pre-2.0/
```

Recordings in `data/` can stay; the directory is ignored from 2.0 on.

## 3 · Presence service: CEC port

The unit now addresses `/dev/cec0` (display cable in HDMI0). If your cable sits in the other socket,
keep `cec1` — the [HDMI wiring and CEC](hardware.md#hdmi-wiring-and-cec) section shows how to tell.

```bash
sudo cp systemd/presence.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart presence
journalctl -u presence -n 20                # no "Not Acknowledged" on the next switch
```

## 4 · Calendar module from the fork

`modules.txt` now points `MMM-MyGCalendar` at the fork with the Today panel, pinned to `d7db1d1`.
`bootstrap.sh` updates existing modules but does not change their remote, so switch it first:

```bash
git -C ~/Projects/MagicMirror/modules/MMM-MyGCalendar remote set-url origin \
    https://github.com/bikenthusiast/MMM-MyGCalendar
./scripts/bootstrap.sh
systemctl --user restart magicmirror
```

## 5 · Gesture sensor (SEN0628)

Wiring, protocol and troubleshooting are in [sen0628.md](sen0628.md), the decision in
[ADR-007](adr/007-gesture-sensor.md).

> [!CAUTION]
> **3.3 V only.** The sensor's data lines follow its supply; on 5 V they put 5 V on GPIO 12/13.

1. Set the sensor's mode switch to UART. Wire 3V3 → pin 1, GND → pin 34, sensor RX (C/R) → pin 32,
   sensor TX (D/T) → pin 33.
2. Add `dtoverlay=uart5` to `/boot/firmware/config.txt`, then shut down and **cut the power** — the
   sensor reads its mode switch only at power-up, and a reboot does not power-cycle it.
3. Check:
   ```bash
   pinctrl get 12,13                        # TXD5 / RXD5
   python3 -m pip install --user pyserial   # if python3-serial is not installed
   python3 scripts/tof_test.py              # 4x4 grid, ~17-25 fps
   ```
4. Test the action, then the detector:
   ```bash
   ./scripts/gesture-action.sh SWIPE_LEFT   # QR code appears
   python3 scripts/gesture.py --exec "scripts/gesture-action.sh {gesture}"
   ```
5. Service:
   ```bash
   sudo cp systemd/gesture.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now gesture
   ```

If pi-edge-ai reads the sensor itself (step 6), leave `gesture.service` disabled: only one process may
use `/dev/ttyAMA5`.

## 6 · Edge bridge (pi-edge-ai)

Only if pi-edge-ai and its MQTT broker run on this Pi. Installation is in the header of
`systemd/edge-bridge.service` and in [ADR-008](adr/008-edge-event-bridge.md): `python3-paho-mqtt`,
`/etc/magicmirror/edge-bridge.env` from `config/edge-bridge.env.example`, then enable the unit.

## 7 · Automatic deployment

Full steps and background: [docs/cicd/README.md](cicd/README.md#installation-on-the-pi). In short:

```bash
git remote set-url origin https://github.com/bikenthusiast/raspberrypi-magicmirror.git
git remote set-url --push origin git@github.com:bikenthusiast/raspberrypi-magicmirror.git
# sudoers rule for the presence / edge-bridge restarts (see docs/cicd)
cp systemd/deploy-user.service ~/.config/systemd/user/deploy.service
cp systemd/deploy-user.timer   ~/.config/systemd/user/deploy.timer
systemctl --user daemon-reload
scripts/deploy.sh --dry-run
systemctl --user enable --now deploy.timer
```

---

## Check

```bash
curl -fsS -o /dev/null http://localhost:8080 && echo "mirror up"
systemctl --user is-active magicmirror
systemctl is-active presence
systemctl is-active gesture edge-bridge 2>/dev/null       # whichever you installed
systemctl --user list-timers deploy.timer                 # if step 7
./scripts/guest-page.sh show; sleep 5; ./scripts/guest-page.sh hide
```

## Back to 1.0

```bash
systemctl --user disable --now deploy.timer 2>/dev/null
sudo systemctl disable --now gesture edge-bridge 2>/dev/null
git switch --detach v1.0
sudo cp systemd/presence.service /etc/systemd/system/ && sudo systemctl daemon-reload
sudo systemctl restart presence
systemctl --user restart magicmirror
```

`config/secrets.js` and `data/` are not touched by any of this.
