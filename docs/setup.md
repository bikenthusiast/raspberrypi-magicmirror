# Setup from scratch

Full rebuild on a fresh microSD card. This document is also the test: whatever
is missing here is missing from the repo.

> [!NOTE]
> **Status: updated 09.09.2026, not yet walked through end to end.**
>
> Sections marked `<!-- TODO -->` need filling in during the rebuild. Anything
> you have to look up, guess, or fetch from the old card is a gap — note it as
> you go rather than reconstructing afterwards.
>
> Recording the session helps:
>
> ```bash
> mkdir -p ~/logs
> script -f ~/logs/setup-$(date +%F).txt
> ```
>
> That transcript will contain every token you type. Delete it once you have
> extracted what you need, and keep it out of the repo.

**Last full run:** <!-- TODO: date -->
**Duration:** <!-- TODO -->

---

## What the finished system does

| | |
|---|---|
| 07:30 | Witty Pi powers the Pi on |
| boot | user session starts, kanshi rotates the display, Electron renders MagicMirror |
| daytime | radar sensor switches the panel via HDMI-CEC |
| 22:15 | Witty Pi powers the Pi off |

No login required at any point.

---

## 0 · Prerequisites

### Hardware

| Part | Notes |
|---|---|
| Raspberry Pi 4B, 8 GB | |
| microSD | 128 GB |
| Official USB-C PSU, 5.1 V / 3 A | plugs into the **Witty Pi**, not the Pi |
| UUGear Witty Pi 4 Mini | RTC and power scheduling |
| 2×20 GPIO stacking header | not included with the Witty Pi |
| M2.5 spacers, 10 and 12 mm | measure the gap before choosing |
| Waveshare HMMD mmWave sensor | presence detection |
| Monitor | MSI PRO MP273QW E14, 2560×1440, **CEC enabled in the OSD** |
| micro-HDMI to HDMI cable | must carry pin 13 for CEC |

### On the development machine

Raspberry Pi Imager, and an SSH key.

---

## 1 · Write the card

> [!IMPORTANT]
> The advanced options in Imager (gear icon, or `Ctrl+Shift+X`) are not
> optional. Without them there is no SSH and no WiFi, and you need a monitor
> and keyboard to get in at all.

| Field | Value |
|---|---|
| Device | Raspberry Pi 4 |
| OS | <!-- TODO: exact name. Desktop is required — Electron needs a compositor --> |
| Hostname | `raspberrypi` |
| Username | `tobiask` |
| SSH | enabled, **public key** |
| Public key | <!-- TODO: which key --> |
| WiFi SSID | <!-- TODO --> |
| WiFi country | DE — without this the interface may stay down |
| Locale | Europe/Berlin, de-DE |

> [!CAUTION]
> The username must be `tobiask`. Paths in scripts, systemd units and the
> deploy script are hard-wired to it.

**Desktop, not Lite.** Electron renders into a Wayland session, so labwc has to
be present. Server mode would work headless, but then nothing appears on the
monitor.

---

## 2 · First connection

```bash
ssh tobiask@raspberrypi.local
```

> [!TIP]
> For mDNS or IPv6 trouble, `AddressFamily inet` in `~/.ssh/config` forces
> IPv4:
>
> ```
> Host pi
>     HostName raspberrypi.local
>     User tobiask
>     AddressFamily inet
> ```

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

<!-- TODO: how long did this take? -->

---

## 3 · System settings

> [!CAUTION]
> Set these **before** mounting the Witty Pi. With 1-Wire active on GPIO 4 the
> Pi shuts down immediately after every boot and there is no chance to log in.

```bash
sudo raspi-config nonint do_i2c 0          # I²C for the Witty Pi
sudo raspi-config nonint do_serial_hw 0    # hardware UART
sudo raspi-config nonint do_serial_cons 1  # serial login shell OFF
```

Verify after a reboot:

```bash
sudo raspi-config nonint get_i2c            # 0 = enabled
sudo raspi-config nonint get_serial_cons    # 1 = disabled
ls -l /dev/serial*                          # serial0 -> ttyAMA0
grep -n "w1-gpio" /boot/firmware/config.txt # must stay empty
```

Note the inverted conventions: for `serial_cons`, `1` means disabled; for
`i2c` and `serial_hw`, `0` means enabled.

---

## 4 · Packages

```bash
sudo apt install -y \
  git tmux zsh qrencode \
  i2c-tools v4l-utils \
  python3-gpiozero python3-lgpio \
  kanshi
```

| Package | Needed for |
|---|---|
| `i2c-tools` | talking to the Witty Pi. Binary lives in `/usr/sbin` |
| `v4l-utils` | `cec-ctl`, the display switching |
| `python3-gpiozero`, `python3-lgpio` | reading the radar sensor |
| `kanshi` | display rotation |
| `qrencode` | generating the guest WiFi QR code |

> [!TIP]
> `/usr/sbin` is not on the interactive PATH by default. Add to `~/.zshrc`:
>
> ```zsh
> export PATH="$PATH:/usr/sbin"
> ```

<!-- TODO: zsh / oh-my-zsh setup if used -->

---

## 5 · Node.js

> [!IMPORTANT]
> Version matters. The working setup runs **Node 24.17**, which `apt install
> nodejs` does not provide on Trixie.

<!-- TODO: how was Node 24 actually installed? NodeSource, nvm, fnm? -->

```bash
node --version    # expect v24.x
npm --version
```

---

## 6 · MagicMirror

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/MagicMirrorOrg/MagicMirror.git
cd MagicMirror
npm install --omit=dev
```

Slow on the Pi. Use `tmux` so a dropped connection doesn't abort it.

<!-- TODO: duration, warnings, disk space -->

---

## 7 · Own repository

```bash
cd ~/Projects
git clone git@github.com:bikenthusiast/raspberrypi-magicmirror.git
cd raspberrypi-magicmirror
git config core.hooksPath .githooks
```

> [!IMPORTANT]
> `core.hooksPath` is a local setting and does not travel with the repo.
> Without it the pre-commit secret check never runs.

---

## 8 · Modules

```bash
./scripts/bootstrap.sh ~/Projects/MagicMirror
```

<!-- TODO: did the script run cleanly? -->

> [!CAUTION]
> Folder names must match the module name in the config **exactly**, case
> included. A configured but missing module produces a 404 in the loader, the
> script chain aborts, and **every** subsequent module fails to start — the
> screen stays completely black.

### Patch the two Fabrizz modules

> [!WARNING]
> Both modules bundle `node-fetch` 2.7.0, which fails to decompress gzip
> response bodies on Node 18 and later. The symptom is
> `ERR_STREAM_PREMATURE_CLOSE` thrown at `Gunzip`, in a retry loop that only a
> restart clears.
>
> `MMM-OnSpotify/utils/SpotifyFetcher.js`, lines 10–11:
>
> ```js
> const fetch = globalThis.fetch ?? require("node-fetch");
> const Headers = globalThis.Headers ?? fetch.Headers;
> ```
>
> `MMM-LiveLyrics/utils/LyricsFetcher.js`, line 14:
>
> ```js
> const fetch = globalThis.fetch ?? require("node-fetch");
> ```
>
> Reported upstream as
> [MMM-OnSpotify#116](https://github.com/Fabrizz/MMM-OnSpotify/issues/116);
> the maintainer has said a fix will follow. Once it lands these patches can
> be dropped — until then a `git pull` on either module silently reverts them.

---

## 9 · Secrets

```bash
cp ~/Projects/raspberrypi-magicmirror/.env.example ~/Projects/MagicMirror/.env
chmod 600 ~/Projects/MagicMirror/.env
$EDITOR ~/Projects/MagicMirror/.env
```

| Value | Source |
|---|---|
| `MM_REMOTE_API_KEY` | `openssl rand -hex 16` |
| `GUEST_WIFI_SSID`, `GUEST_WIFI_PASS` | FRITZ!Box → WLAN → guest access |
| `GCAL_ICAL_URL` | Google Calendar → settings → private iCal address |
| Spotify client ID / secret | developer.spotify.com/dashboard |
| Spotify access / refresh token | authorisation flow, see below |
| Genius API token | genius.com/api-clients, for MMM-LiveLyrics |

### Spotify authorisation

> [!WARNING]
> The redirect URI must be `http://127.0.0.1:8888/callback`. Spotify has
> rejected `localhost` since 2025 — both in the dashboard and in module code.
>
> Run the authorisation on the development machine, not the Pi. It only
> produces tokens, which are then copied across, and it saves setting up a
> second SSH tunnel.

<!-- TODO: concrete steps once done again -->

### Guest WiFi QR code

```bash
cd ~/Projects/raspberrypi-magicmirror
./scripts/make-guest-qr.sh
```

Writes `guest-wifi.png` into the module folder. Gitignored — it encodes the
password.

---

## 10 · Symlinks

> [!CAUTION]
> Easy to forget during a rebuild. Without these MagicMirror finds neither the
> configuration nor the two custom modules.

```bash
ln -sfn ~/Projects/raspberrypi-magicmirror/config/config.js \
        ~/Projects/MagicMirror/config/config.js

ln -sfn ~/Projects/raspberrypi-magicmirror/modules/MMM-SpotifyPages \
        ~/Projects/MagicMirror/modules/MMM-SpotifyPages

ln -sfn ~/Projects/raspberrypi-magicmirror/modules/MMM-GuestWifi \
        ~/Projects/MagicMirror/modules/MMM-GuestWifi
```

> [!TIP]
> `ln -sfn`, not `ln -s`. If the target already exists as a directory, `ln -s`
> places the link **inside** it — everything ends up one level too deep and is
> never found.

The real `config.js` is gitignored, so create it from the example:

```bash
cd ~/Projects/raspberrypi-magicmirror
cp config/config.js.example config/config.js
$EDITOR config/config.js    # replace the placeholders
```

Check:

```bash
ls -l  ~/Projects/MagicMirror/modules/ | grep -E "SpotifyPages|GuestWifi"
ls -lL ~/Projects/MagicMirror/config/config.js
node -e "require('$HOME/Projects/MagicMirror/config/config.js')"
```

The last one catches runtime errors that `node --check` misses — a module name
without quotes, for instance, which JavaScript reads as a subtraction.

---

## 11 · Display

Three pieces: rotation, autostart, user service.

### Rotation via kanshi

```bash
mkdir -p ~/.config/kanshi
cp ~/Projects/raspberrypi-magicmirror/config/desktop/kanshi.conf \
   ~/.config/kanshi/config
```

> [!NOTE]
> A one-off `wlr-randr --transform 90` does not hold. Electron resets the
> transform on start, and the monitor renegotiates the HDMI signal when waking
> from CEC standby. kanshi reapplies the profile on both events.
>
> The profile matches on make, model and serial rather than the connector
> name, so it survives a change in port enumeration.

<!-- TODO: adjust identifier if the monitor differs -->

### labwc autostart

```bash
mkdir -p ~/.config/labwc
cp ~/Projects/raspberrypi-magicmirror/config/desktop/labwc-autostart \
   ~/.config/labwc/autostart
```

Contains only `kanshi &`. MagicMirror is started by the user service — putting
it here as well produces two instances fighting over port 8080.

### User service

```bash
mkdir -p ~/.config/systemd/user
cp ~/Projects/raspberrypi-magicmirror/systemd/magicmirror-user.service \
   ~/.config/systemd/user/magicmirror.service

systemctl --user daemon-reload
systemctl --user enable --now magicmirror
sudo loginctl enable-linger tobiask
```

> [!IMPORTANT]
> `enable-linger` is essential. Without it user services only run while an
> interactive session exists — and nobody logs in when the Pi powers up at
> 07:30.
>
> The unit binds to `default.target`, not `graphical-session.target`: the
> latter never becomes active under labwc.

---

## 12 · Witty Pi

> [!CAUTION]
> Power down properly and unplug before mounting. Pulling the board from a
> running Pi cost the WiFi credentials once and caused a filesystem dropout
> another time.
>
> **Note where the fan is connected first** — pins 1 and 6. Once the board is
> on, those pins are unreachable and the fan has to be reconnected on top of
> the stacking header.

```bash
mkdir -p ~/Projects && cd ~/Projects
wget https://www.uugear.com/repo/WittyPi4/install.sh
sudo sh install.sh
```

Mounting:

1. `sudo shutdown -h now`, wait for the green LED, unplug
2. Stacking header onto the GPIO pins — flush, all 40, no offset
3. **Measure the board gap** — decides between 10 mm and 12 mm spacers
4. Spacers through the mounting holes, secured with M2.5 nuts
5. Witty Pi onto the header. Press down with a steel ruler laid across both
   pin rows; fingers tilt it
6. Four short M2.5 screws, tightened crosswise
7. Reconnect the fan, then the radar sensor
8. **PSU into the Witty Pi's USB-C**, not the Pi's
9. Press the button — default power-on state is OFF

```bash
sudo i2cdetect -y 1     # address 08 must appear
cd ~/Projects/wittypi && ./wittyPi.sh
```

### Two settings

| Setting | Default | Required |
|---|---|---|
| Default state when powered | OFF | **ON** — otherwise the mirror stays dark after a power cut |

Menu item 11. Then the schedule via item 6, using `mirror.wpi`.

<!-- TODO: copy mirror.wpi into the repo -->

> [!TIP]
> If `schedule.wpi` is owned by root the copy fails silently and an old
> schedule stays active:
>
> ```bash
> sudo chown -R tobiask:tobiask ~/Projects/wittypi
> ```

The log at `~/Projects/wittypi/wittyPi.log` states plainly why each transition
happened — scheduled, button, or interrupted.

---

## 13 · Presence detection

### Wiring

| Sensor | Pi pin | GPIO |
|---|---|---|
| 3V3 | **17** | — |
| GND | **9** | — |
| OT2 | **13** | GPIO 27 |

> [!WARNING]
> **3.3 V, not 5 V.** Pin 2 destroys the module. Pins 1 and 6 are taken by the
> fan, hence the alternatives.

TX and RX stay unconnected. TX would occupy GPIO 14, which the Witty Pi
monitors to detect shutdown. Sensor configuration is done separately over the
FT232 adapter (115200 8N1).

Test:

```bash
watch -n 0.5 pinctrl get 27
```

`hi` in front of the sensor, `lo` when out of range.

### Service

```bash
cd ~/Projects/raspberrypi-magicmirror
sudo cp systemd/presence.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now presence
journalctl -u presence -f
```

> [!NOTE]
> The panel is switched over **HDMI-CEC**, not the compositor. Under labwc both
> `wlopm` and `wlr-randr --off` disable the output instead of putting the panel
> into standby; re-enabling then fails roughly half the time and each cycle
> leaks another headless output.
>
> CEC goes over pin 13 straight to the monitor's own controller. The Pi's
> output stays configured throughout.
>
> **Device node:** `/dev/cec1`, not `cec0`. The Pi 4 exposes one per HDMI port,
> and the wrong one fails with `errno=64` and no further explanation.
>
> Requires CEC enabled in the monitor's OSD.

Manual check:

```bash
cec-ctl -d /dev/cec1 --playback --osd-name "MagicMirror"
cec-ctl -d /dev/cec1 --to 0 --standby
cec-ctl -d /dev/cec1 --to 0 --image-view-on
```

---

## 14 · Verification

| Check | Expected |
|---|---|
| Reboot without login | mirror appears, rotated |
| Clock, weather, MVG, news | visible |
| Page rotation | alternates every 5 minutes |
| Spotify | starting a track switches to page 2 with lyrics |
| Guest WiFi | `SHOW_HIDDEN_PAGE/gast` displays the QR code, scans |
| Presence | panel goes dark after the grace period, wakes on approach |
| Schedule | powers down at 22:15, comes back at 07:30 |
| Logs | `~/Projects/MagicMirror/logs/magicmirror.log` grows across reboots |

<!-- TODO: what failed on the first run? -->

### Guest page over HTTP

```bash
KEY=$(grep -oP 'apiKey:\s*"\K[^"]+' ~/Projects/MagicMirror/config/config.js)

curl -H "Authorization: apiKey $KEY" \
     "http://localhost:8080/api/notification/SHOW_HIDDEN_PAGE/gast"
```

> [!IMPORTANT]
> The API key goes in the **header**, not the URL, and the page name is a path
> segment. With a query string present, MMM-Remote-Control wraps the payload
> in an object and MMM-pages reports
> `Hidden page "[object Object]" does not exist!`

---

## 15 · Logging

MagicMirror writes to a file via the user service:

```
StandardOutput=append:/home/tobiask/Projects/MagicMirror/logs/magicmirror.log
StandardError=append:/home/tobiask/Projects/MagicMirror/logs/magicmirror.log
```

Appends across restarts and reboots.

> [!NOTE]
> The systemd journal is **not** persistent on this system despite
> `Storage=persistent` in `journald.conf`. The cause is unresolved — journald
> reports no error and simply keeps using `/run/log/journal`. The file-based
> route above sidesteps it.

Log rotation is not yet configured. `/etc/logrotate.d/magicmirror` with
`copytruncate` so the running service keeps its file handle.

<!-- TODO: set up logrotate -->

> [!CAUTION]
> The log contains API tokens in URLs — the Genius token appears in full in
> every lyrics request. `logs/` must be gitignored; the pre-commit hook checks
> text patterns but would not necessarily catch a token embedded in a URL.

---

## Follow-up

- [ ] All `<!-- TODO -->` replaced
- [ ] Date and duration recorded at the top
- [ ] New pitfalls added to `troubleshooting.md`
- [ ] `mirror.wpi` copied into the repo
- [ ] Commit pins added to `modules.txt`
- [ ] logrotate configured

> [!NOTE]
> Anything you had to look up in old notes or chat logs during the rebuild is a
> gap. Note it immediately — reconstructing it in the evening does not work.