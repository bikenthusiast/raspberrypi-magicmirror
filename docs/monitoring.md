# Monitoring and self-healing

How the mirror notices that something is wrong, tells you, and recovers on its own where it can.
The decision behind it: [ADR-010](adr/010-health-check-alerts.md).

| Layer | What it covers | Where |
|---|---|---|
| Health check, once a minute | Power, temperature, memory, disk, MagicMirror, internet. Alerts on the mirror and the phone | `scripts/health-check.sh`, `systemd/health-check-user.*` |
| `Restart=on-failure` | A crashed MagicMirror, single crashes | `systemd/magicmirror-user.service` |
| Health check restart | MagicMirror left `failed` after systemd gave up restarting it | `scripts/health-check.sh` |
| Hardware watchdog | The whole Pi freezes: no SSH, no mouse, frozen screen | `/etc/systemd/system.conf` (below) |

---

## What is checked

| Check | Alerts when | After | Typical cause |
|---|---|---|---|
| `power` | `vcgencmd get_throttled` has bit 0 (under-voltage now, priority *urgent*) or bit 16 (since boot) | 1 run | Supply, cable, load on the 5 V pins; see [hardware.md](hardware.md#power-supply) |
| `temperature` | CPU ≥ 75 °C | 2 runs | Fan not running; the Pi 4 throttles at 80 °C |
| `memory` | MemAvailable < 500 MB | 2 runs | A module leaking memory in Electron |
| `disk` | Root file system ≥ 90 % | 1 run | Logs, recordings in `data/` |
| `magicmirror` | `magicmirror.service` not `active` | 3 runs | Crash, failed start, or stopped by hand |
| `network` | No ping reply from 1.1.1.1 or 9.9.9.9 | 3 runs | See below: the alert says whether the LAN or only the internet is down |
| `security-updates` | Debian security updates still pending | 2 days | `unattended-upgrades` not installed or failing; see [updates.md](updates.md) |
| `os-updates` | Any OS update pending (priority *low*, phone only) | 35 days | The monthly `apt full-upgrade` is overdue |

Every value can be changed with an environment variable (`HEALTH_TEMP_MAX_C`, `HEALTH_MEM_MIN_MB`,
…, see the top of the script), for example in a drop-in for the service:

```bash
systemctl --user edit health-check.service
# [Service]
# Environment=HEALTH_TEMP_MAX_C=70
```

An alert fires **once** when a check goes bad and once more when it is OK again; the recovery message
carries the start time and the duration. A check that stays bad does not repeat every minute. The state
lives in `~/.local/state/mirror-health/`.

`network` pings the router (the IPv4 default gateway, or `HEALTH_GATEWAY`) when the internet hosts do
not answer, and the journal line shows the result as `net=ok`, `net=no-internet` or `net=no-lan`:

| `net=` | Meaning | Look at |
|---|---|---|
| `no-internet` | The router answers, the internet does not | Router event log (internet / DSL), provider |
| `no-lan` | The router does not answer, or there is no default route | `journalctl -u NetworkManager -b`, `journalctl -u wpa_supplicant -b` (disconnect `reason=`) |

`no-lan` while Wi-Fi still shows as connected is a link that carries no traffic. The router usually ends
it after a few minutes with a deauthentication (`reason=2`), and the Pi reconnects.

`power` alerts at most once per boot: bit 16 stays set until the next reboot, and the recovery message
comes after a reboot without under-voltage.

## Alert channels

- **Mirror:** a notification in the corner through MMM-Remote-Control and the default `alert` module,
  60 s on screen. Needs `remoteApiKey` in `secrets.js`, which the mirror already uses. Not shown when
  MagicMirror itself is down or the panel is in standby, so it is the secondary channel.
- **Phone:** a push message via [ntfy](https://ntfy.sh). Install the ntfy app, subscribe to your
  topic, and set it in `config/secrets.js`:

  ```js
  healthNtfyTopic: "mirror-<random>",      // openssl rand -hex 12
  healthNtfyServer: "https://ntfy.sh",     // or a self-hosted server
  ```

  ntfy topics are public by name: anyone who knows the topic can read the alerts and post to it.
  A long random name is the access control, which is why it lives in `secrets.js`. Without a topic
  there are no phone alerts; everything else works.

  While the internet is down, phone alerts cannot leave. The mirror shows the `network` alert; the
  phone gets the "OK again" message with the duration once the connection is back.

## Install

```bash
cd ~/Projects/raspberrypi-magicmirror
cp systemd/health-check-user.service ~/.config/systemd/user/health-check.service
cp systemd/health-check-user.timer   ~/.config/systemd/user/health-check.timer
systemctl --user daemon-reload
systemctl --user enable --now health-check.timer

scripts/health-check.sh --dry-run     # current values and verdicts, sends nothing
scripts/health-check.sh --test        # one test alert through both channels
```

User units only run without a login session with lingering enabled (`loginctl enable-linger`), which
the mirror already needs for MagicMirror ([setup.md](setup.md)).

If the provisional cron job from the October 2026 freeze investigation is still installed, remove it
with `crontab -e`; the journal now has the same values every minute.

## Read

```bash
journalctl -t health -b                       # every run of this boot
journalctl -t health -p warning -b            # alerts and recoveries only
journalctl -t health -b -1 -n 15              # the last minutes before a freeze or reboot
systemctl --user list-timers health-check.timer
```

`-t health`, not `--user -u health-check`, for the same reason as with MagicMirror
([logging.md](logging.md)).

## Hardware watchdog

The health check cannot help when the Pi itself freezes. The BCM2711 has a hardware watchdog: systemd
feeds it, and if systemd stops responding the chip resets the Pi.

```bash
sudo sed -i 's/^#\?RuntimeWatchdogSec=.*/RuntimeWatchdogSec=15/' /etc/systemd/system.conf
sudo systemctl daemon-reexec
systemctl show -p RuntimeWatchdogUSec          # 15s
```

After a watchdog reset, `journalctl --list-boots` shows a new boot without a clean shutdown before it,
and `journalctl -t health -b -1` shows the last measurements before the freeze.

This is system configuration, not a file in the repository, so `deploy.sh` does not install it.
