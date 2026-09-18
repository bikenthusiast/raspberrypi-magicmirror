# Setup from scratch

Full rebuild on a fresh microSD card.

> [!NOTE]
> `<!-- TODO -->` are open.
>
> Record the session — it saves reconstructing afterwards:
>
> ```bash
> mkdir -p ~/logs
> script -f ~/logs/setup-$(date +%F).txt
> ```
>
> That transcript will contain every token you type. Delete it once you have
> what you need, and keep it out of the repo.

**Last full run:** 14.09.2026
**Duration:** ~2 h from blank card to a working mirror (sections 1–13).
Sections 14–15 not included.

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
| Fan, 2-wire | see the pin note in section 12 |
| Monitor | MSI PRO MP273QW E14, 2560×1440, **CEC enabled in the OSD** |
| micro-HDMI to HDMI cable | must carry pin 13 for CEC |

### On the development machine

1. Install [Raspberry Pi Imager](https://www.raspberrypi.com/software/)

2. Create an SSH key via:

```bash
ssh-keygen -t rsa
```

RSA rather than ed25519 because that is what the Imager field was filled with;
either works, but the client must be told which one — see section 2.

---

## 1 · Write the card

> [!IMPORTANT]
> The advanced options in Imager (gear icon, or `Ctrl+Shift+X`) are not
> optional. Without them there is no SSH and no WiFi.

| Field | Value |
|---|---|
| Device | Raspberry Pi 4 |
| OS | Raspberry Pi OS (64-bit), **Desktop** — Electron needs a compositor |
| Hostname | pick a unique name — referred to below as `<hostname>` |
| Username | `tobiask` |
| Password | see the note below |
| SSH | enabled, **public key** |
| Public key | contents of `~/.ssh/id_rsa.pub`, pasted as text |
| WiFi SSID | `your_wifi_ssid` |
| WiFi country | DE — without this the interface may stay down |
| Locale | Europe/Berlin, de-DE |

> [!CAUTION]
> The username must be `tobiask`. Paths in scripts, systemd units and the
> deploy script are hard-wired to it.
>
> The **hostname** is free to choose, and a distinct one per card avoids the
> confusion of two machines answering to `raspberrypi.local`. Substitute it
> wherever `<hostname>` appears below.

**Desktop, not Lite.** Electron renders into a Wayland session, so labwc has to
be present.

> [!WARNING]
> **Decide about the password deliberately.** Leaving the field empty means no
> password is set, `sudo` works without one, and `chsh` fails with
> `PAM: Authentication failure` because there is nothing to authenticate
> against.
>
> Either set one in Imager, or afterwards:
>
> ```bash
> sudo passwd tobiask
> ```
>
> Without a password, use `sudo chsh -s $(which zsh) tobiask` in section 4.

**The SSH key is pasted as text**, not chosen as a file. Print it with:

```bash
cat ~/.ssh/id_rsa.pub
```

---

## 2 · First connection

> [!IMPORTANT]
> **Rebuilding onto the same hostname:** the new card has different host keys,
> so SSH refuses with `REMOTE HOST IDENTIFICATION HAS CHANGED`. Clear the old
> entries on the development machine first:
>
> ```bash
> ssh-keygen -R <hostname>.local
> ssh-keygen -R <ip-address>
> ```

```bash
ssh -i ~/.ssh/id_rsa tobiask@<hostname>.local
```

> [!TIP]
> The `-i` is necessary until `~/.ssh/config` is set up: the client offers
> `id_ed25519` first and is refused before it ever tries RSA.
>
> ```
> Host pi
>     HostName <hostname>.local
>     User tobiask
>     IdentityFile ~/.ssh/id_rsa
>     AddressFamily inet
> ```
>
> SSH also ignores a private key whose permissions are looser than `600`:
>
> ```bash
> chmod 600 ~/.ssh/id_rsa
> ```

First boot takes longer than usual — the filesystem is resized and host keys
are generated. `Connection refused` in the first minutes is normal.

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

<!-- TODO: duration -->

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

The conventions are inverted: for `serial_cons`, `1` means disabled; for `i2c`
and `serial_hw`, `0` means enabled.

---

## 4 · Shell

Raspberry Pi OS ships bash. The setup assumes zsh.

```bash
sudo apt install -y zsh
chsh -s $(which zsh)          # or: sudo chsh -s $(which zsh) tobiask
```

Takes effect at next login.

**oh-my-zsh**, if you want the same prompt as before. Run this *first* — its
installer replaces `~/.zshrc`:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Then the exports:

```bash
echo 'export EDITOR=nano' >> ~/.zshrc
echo 'export PATH="$PATH:/usr/sbin"' >> ~/.zshrc
```

> [!TIP]
> `EDITOR` is not set by default. `$EDITOR somefile` then expands to nothing
> and the shell tries to *execute* the file — which reports `Permission denied`
> and looks like a rights problem.
>
> `/usr/sbin` is not on the interactive PATH either, which is why `i2cdetect`
> and `hwclock` appear to be missing.

Autosuggestions and highlighting:

```bash
sudo apt install -y zsh-autosuggestions zsh-syntax-highlighting
```

At the **end** of `~/.zshrc`, highlighting last — it wraps the line editor and
breaks if anything wraps it afterwards:

```zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

---

## 5 · Packages

```bash
sudo apt install -y \
  git tmux qrencode \
  i2c-tools v4l-utils \
  python3-gpiozero python3-lgpio \
  kanshi
```

| Package | Needed for |
|---|---|
| `i2c-tools` | talking to the Witty Pi |
| `v4l-utils` | `cec-ctl`, the display switching |
| `python3-gpiozero`, `python3-lgpio` | reading the radar sensor |
| `kanshi` | display rotation |
| `qrencode` | generating the guest WiFi QR code |

---

## 6 · Node.js

> [!IMPORTANT]
> **Install before checking the version.** `apt install nodejs` does not
> provide Node 24 on Trixie.

Via NodeSource, which pins a major version and stays reproducible:

```bash
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
```

The first command adds the NodeSource repository and its signing key; the
second installs from it rather than from Debian's own packages.

```bash
node --version    # expect v24.x
npm --version
```

---

## 7 · MagicMirror

```bash
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/MagicMirrorOrg/MagicMirror.git
cd MagicMirror
npm install --omit=dev
```

Slow on the Pi. Use `tmux` so a dropped connection doesn't abort it.

<!-- TODO: duration, disk space -->

---

## 8 · GitHub access

> [!IMPORTANT]
> The Pi needs **its own** SSH key. A key added from the development machine
> authenticates that machine, not this one.

```bash
ssh-keygen -t ed25519 -C "raspberrypi-magicmirror"
cat ~/.ssh/id_ed25519.pub
```

Paste into GitHub: Settings → SSH and GPG keys → New SSH key.

Verify:

```bash
ssh -T git@github.com
```

Expect `Hi <username>! You've successfully authenticated`.

HTTPS is the alternative if the Pi only ever pulls:

```bash
git clone https://github.com/bikenthusiast/raspberrypi-magicmirror.git
```

---

## 9 · Own repository

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

## 10 · Secrets

All credentials live in one gitignored file, which `config.js` reads.

```bash
cd ~/Projects/raspberrypi-magicmirror
cp config/secrets.example.js config/secrets.js
chmod 600 config/secrets.js
grep -q "^config/secrets.js$" .gitignore || echo "config/secrets.js" >> .gitignore
nano config/secrets.js
```

> [!CAUTION]
> **Key names are case-sensitive and silently ignored when wrong.** A
> misspelled key yields `undefined` rather than an error — the file loads,
> `config.js` loads, MagicMirror starts, and the fault only surfaces later as
> a `400` from an API in a module log.
>
> `spotifyClientID` instead of `spotifyClientId`, and `spotifyClienSecret`
> missing a `t`, cost half an hour on 14.09.
>
> The startup check at the top of `config.js` catches this. Verify what is
> actually in the file:
>
> ```bash
> node -e "console.log(Object.keys(require('$PWD/config/secrets.js')))"
> ```

| Value | Source |
|---|---|
| `remoteApiKey` | `openssl rand -hex 16` |
| `guestWifiSsid`, `guestWifiPass` | FRITZ!Box → WLAN → guest access |
| `calendarUrl` | Google Calendar → settings → private iCal address |
| `spotifyClientId`, `spotifyClientSecret` | developer.spotify.com/dashboard |
| `spotifyAccessToken`, `spotifyRefreshToken` | authorisation flow, below |
| `geniusAccessToken` | genius.com/api-clients |
| `mvgStation` | MVG stop name, exactly as spelled |

> [!WARNING]
> **Genius: use "Generate Access Token", not the Client Secret.** The wrong one
> produces `invalid_token` from the API and
> `TypeError: Cannot read properties of undefined (reading 'hits')` in the
> lyrics module — an error that points nowhere near the cause.

### Verify the values before starting

Length check — client ID and secret are exactly 32 hex characters each:

```bash
node -e "
const s = require('$PWD/config/secrets.js');
for (const k of Object.keys(s)) console.log(k.padEnd(22), String(s[k]||'').length);
"
```

Then test each API directly, so a failure points at the credential rather than
at a module:

```bash
S=$PWD/config/secrets.js
CID=$(node -e "console.log(require('$S').spotifyClientId)")
CSEC=$(node -e "console.log(require('$S').spotifyClientSecret)")
REF=$(node -e "console.log(require('$S').spotifyRefreshToken)")

curl -s -X POST https://accounts.spotify.com/api/token \
  -u "$CID:$CSEC" -d grant_type=refresh_token -d refresh_token="$REF" | head -c 120
```

An `access_token` means the chain works. `invalid_client` points at ID or
secret, `invalid_grant` at the refresh token.

```bash
TOKEN=$(node -e "console.log(require('$S').geniusAccessToken)")
curl -s "https://api.genius.com/search?q=test&access_token=$TOKEN" | head -c 80
```

`{"meta":{"status":200` means the Genius token is right.

> [!IMPORTANT]
> **Typographic quotes break the file.** Credentials pasted through a browser
> field can carry `"` instead of `"`, which produces
> `SyntaxError: Invalid or unexpected token`.
>
> The error is reported at the `require` line in `config.js`, not inside
> `secrets.js` — Node gives the position of the require, not of the fault.
> Check the real location:
>
> ```bash
> node --check config/secrets.js
> cat -A config/secrets.js | head -20
> ```
>
> `cat -A` renders smart quotes as `M-bM-^@M-^\`.

### Spotify authorisation

The module ships an auth helper — a static page that walks through creating the
Spotify app and produces all four values:

```
https://onsp.fabriz.co/
```

It runs entirely in the browser and stores nothing server-side. The source sits
in the module's `/web` directory as a Vite project, so it can be self-hosted if
you would rather not use the hosted copy.

The tool returns `clientID`, `clientSecret`, `accessToken` and `refreshToken` —
which map to `spotifyClientId`, `spotifyClientSecret`, `spotifyAccessToken` and
`spotifyRefreshToken` in `secrets.js`.

> [!IMPORTANT]
> **Run this on the development machine, not the Pi.** It only produces tokens,
> which are then copied across, and it avoids setting up a second SSH tunnel
> for the callback port.

> [!WARNING]
> Redirect URI must be `http://127.0.0.1:8888/callback`. Spotify has rejected
> `localhost` since 2025, in the dashboard and in module code alike. The helper
> states the URI to register — use exactly what it gives you.

> [!CAUTION]
> **Paste the values through a plain-text step.** Copying straight from a
> browser field into `nano` can carry typographic quotes, which produce
> `SyntaxError: Invalid or unexpected token` — reported against `config.js`
> rather than `secrets.js`.
>
> Verify afterwards: client ID and secret are exactly 32 hex characters each.
>
> ```bash
> node -e "
> const s = require('$PWD/config/secrets.js');
> ['spotifyClientId','spotifyClientSecret'].forEach(k =>
>   console.log(k.padEnd(22), String(s[k]||'').length));
> "
> ```

Test before starting MagicMirror, so a failure points at the credential rather
than at a module:

```bash
S=$PWD/config/secrets.js
CID=$(node -e "console.log(require('$S').spotifyClientId)")
CSEC=$(node -e "console.log(require('$S').spotifyClientSecret)")
REF=$(node -e "console.log(require('$S').spotifyRefreshToken)")

curl -s -X POST https://accounts.spotify.com/api/token \
  -u "$CID:$CSEC" -d grant_type=refresh_token -d refresh_token="$REF" | head -c 120
```

An `access_token` means the chain works. `invalid_client` points at ID or
secret, `invalid_grant` at the refresh token.

---

## 11 · Modules

```bash
cd ~/Projects/raspberrypi-magicmirror
./scripts/bootstrap.sh ~/Projects/MagicMirror
```

The script clones everything in `modules.txt`, applies the node-fetch patches
described below, and symlinks the two modules kept in this repo. It is
idempotent — a second run updates rather than re-cloning.

<details>
<summary>By hand, if the script is unavailable</summary>

```bash
cd ~/Projects/MagicMirror/modules
git clone https://github.com/KoblerS/MMM-MVG.git
git clone https://github.com/jalibu/MMM-RAIN-MAP.git
git clone https://github.com/Jopyth/MMM-Remote-Control.git
git clone https://github.com/edward-shen/MMM-pages.git
git clone https://github.com/edward-shen/MMM-page-indicator.git
git clone https://github.com/LukeSkywalker92/MMM-Globe.git
git clone https://github.com/johnster000/MMM-MyGCalendar.git
git clone https://github.com/Fabrizz/MMM-OnSpotify.git
git clone https://github.com/Fabrizz/MMM-LiveLyrics.git
```

Then `npm install --omit=dev` in each module that declares dependencies, apply
the node-fetch patches manually, and create the two symlinks — all of which the
script would have done. Missing the symlinks is what left Spotify silent on
14.09.

</details>

> [!CAUTION]
> Folder names must match the module name in the config **exactly**, case
> included. A configured but missing module produces a 404 in the loader, the
> script chain aborts, and **every** subsequent module fails to start — the
> screen stays completely black.

### What the node-fetch patch does

Both Fabrizz modules bundle `node-fetch` 2.7.0, which fails to decompress gzip
response bodies on Node 18 and later. The symptom is
`ERR_STREAM_PREMATURE_CLOSE` thrown at `Gunzip`, retried at the poll interval
with no backoff — only a restart clears it.

`bootstrap.sh` rewrites the import in both:

```js
const fetch = globalThis.fetch ?? require("node-fetch");
const Headers = globalThis.Headers ?? fetch.Headers;
```

> [!WARNING]
> **Verify the patch applied cleanly.** The `sed` expression matches an exact
> line; different spacing leaves the file half-patched, which produces:
>
> ```
> Error when loading MMM-OnSpotify: Missing initializer in const declaration
> ```
>
> That message names neither file nor line. Check both:
>
> ```bash
> node --check ~/Projects/MagicMirror/modules/MMM-OnSpotify/utils/SpotifyFetcher.js
> node --check ~/Projects/MagicMirror/modules/MMM-LiveLyrics/utils/LyricsFetcher.js
> ```
>
> Silence means both parse.

Reported upstream as
[MMM-OnSpotify#116](https://github.com/Fabrizz/MMM-OnSpotify/issues/116). Once
fixed there, the patch section in `bootstrap.sh` can go.

---

## 12 · Configuration

```bash
cd ~/Projects/raspberrypi-magicmirror
cp config/config.js.example config/config.js   # if not yet tracked directly
nano config/config.js
```

`config.js` reads the credentials rather than containing them, and uses
`s.remoteApiKey`, `s.calendarUrl` and so on — **without quotes**, since they
are variables. `apiKey: "s.remoteApiKey"` passes the literal string and the
API rejects it.

> [!CAUTION]
> **A relative `require` does not work here.**
>
> ```js
> const s = require("./secrets.js");        // fails
> ```
>
> MagicMirror does not load `config.js` through a normal `require()` — it
> reads and evaluates the file, so there is no file context to resolve `./`
> against. The error is:
>
> ```
> Cannot find module './secrets.js'
> Require stack:
> -
> ```
>
> The bare `-` in the require stack is the tell: the requesting file has no
> name. A symlink does not help, and `node -e "require(...)"` succeeds anyway
> because there the context exists.
>
> Derive the path from the home directory instead:
>
> ```js
> const s = require(require("os").homedir() +
>     "/Projects/raspberrypi-magicmirror/config/secrets.js");
> ```
>
> An absolute literal path works too, but breaks on a rebuild under a
> different username.

### Startup check

Directly after the require, before `let config = {`, sits a block that reports
missing, empty, wrongly sized or misspelled keys. Output goes to `stderr` and
therefore into `magicmirror.log`.

It does not abort — a mirror that refuses to start over a missing Genius token
would be worse than one without lyrics.

After any change to `secrets.js`:

```bash
grep -A 12 "secrets.js" ~/Projects/MagicMirror/logs/magicmirror.log | tail -15
```

### Symlinks

> [!CAUTION]
> Easy to forget. Without these MagicMirror finds neither the configuration nor
> the two custom modules. `bootstrap.sh` handles the modules; the config is
> manual.
>
> On 14.09 both module symlinks were missing because `bootstrap.sh` was not
> run. The mirror started and looked fine — Spotify simply never switched
> pages, and the guest page stayed empty.

```bash
ln -sfn ~/Projects/raspberrypi-magicmirror/config/config.js \
        ~/Projects/MagicMirror/config/config.js
```

> [!TIP]
> `ln -sfn`, not `ln -s`. If the target already exists as a directory, `ln -s`
> places the link **inside** it and everything ends up one level too deep.

Verify:

```bash
ls -lL ~/Projects/MagicMirror/config/config.js
node -e "require('$HOME/Projects/MagicMirror/config/config.js')"
```

Silence from the second means it loads. It catches runtime errors that
`node --check` misses — a module name without quotes, for instance, which
JavaScript reads as a subtraction.

### Guest WiFi QR code

```bash
./scripts/make-guest-qr.sh
```

Writes `guest-wifi.png` into the module folder. Gitignored — it encodes the
password.

---

## 13 · Display

Three pieces: rotation, autostart, user service.

> [!TIP]
> The paths below are relative — run these from inside the repo:
>
> ```bash
> cd ~/Projects/raspberrypi-magicmirror
> ```

```bash
mkdir -p ~/.config/kanshi ~/.config/labwc ~/.config/systemd/user
mkdir -p ~/Projects/MagicMirror/logs

cp config/desktop/kanshi.conf    ~/.config/kanshi/config
cp config/desktop/labwc-autostart ~/.config/labwc/autostart
cp systemd/magicmirror-user.service ~/.config/systemd/user/magicmirror.service

systemctl --user daemon-reload
systemctl --user enable --now magicmirror
sudo loginctl enable-linger tobiask
```

> [!NOTE]
> **Why kanshi rather than a one-off `wlr-randr --transform 90`:** Electron
> resets the transform on start, and the monitor renegotiates the HDMI signal
> when waking from CEC standby. kanshi reapplies the profile on both events.
>
> The profile matches on make, model and serial rather than the connector name,
> so it survives a change in port enumeration.

> [!IMPORTANT]
> **`logs/` must exist before the service starts.** systemd does not create the
> parent directory for `StandardOutput=append:`, and the service fails with
> `status=209/STDOUT` — a code that says nothing about the cause.

> [!IMPORTANT]
> `enable-linger` is essential. Without it user services only run while an
> interactive session exists — and nobody logs in when the Pi powers up at
> 07:30.
>
> The unit binds to `default.target`, not `graphical-session.target`: the
> latter never becomes active under labwc.

The labwc autostart contains only `kanshi &`. Starting MagicMirror there as
well produces two instances fighting over port 8080.

---

## 14 · Witty Pi

> [!NOTE]
> **Most of this is one-time board setup, not per-rebuild work.** The RTC, the
> default power-on state and the schedule live in the Witty Pi's own firmware,
> not on the SD card. Swapping cards leaves all of it intact.
>
> What a rebuild *does* need is the Pi-side software — without it the board
> still switches power on schedule, but nothing responds to the shutdown
> signal, so every cycle becomes a hard power cut:
>
> ```bash
> ls ~/Projects/wittypi/ 2>/dev/null || echo "software missing"
> systemctl status wittypi 2>/dev/null | head -3
> ```

> [!CAUTION]
> Power down properly and unplug before mounting. Pulling the board from a
> running Pi cost the WiFi credentials once and caused a filesystem dropout
> another time.
>
> **Note where the fan is connected first.** Mounting the board covers those
> pins, and forgetting to reconnect leaves the Pi running uncooled — measured
> at 75 °C with throttling, against 61 °C with the fan running.

```bash
cd ~/Projects
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
7. Reconnect the fan and the radar sensor to the header's top row
8. **PSU into the Witty Pi's USB-C**, not the Pi's
9. Press the button — default power-on state is OFF

```bash
sudo i2cdetect -y 1     # address 08 must appear
cd ~/Projects/wittypi && ./wittyPi.sh
```

### Settings

| Setting | Default | Required |
|---|---|---|
| Default state when powered | OFF | **ON** — otherwise the mirror stays dark after a power cut |

Menu item 11. Then the schedule via item 6.

### Schedule

`config/mirror.wpi.example` holds a template. Copy it, adjust the times, and
place it where `wittyPi.sh` looks for schedules:

```bash
cp ~/Projects/raspberrypi-magicmirror/config/mirror.wpi.example \
   ~/Projects/wittypi/schedules/mirror.wpi
nano ~/Projects/wittypi/schedules/mirror.wpi
```

Then menu item 6, and pick `mirror.wpi`.

```
BEGIN   2026-01-01 07:30:00
END     2035-12-31 23:59:59
ON      H14 M45
OFF     H9  M15
```

> [!CAUTION]
> **ON and OFF must add up to 24 hours**, or the cycle drifts a little each
> day. For 07:30–22:15 that is 14 h 45 min ON and 9 h 15 min OFF.
>
> **BEGIN must land on a switch-on moment, and not in the past.** With a past
> date the script can compute the next transition as already due and power the
> Pi down on the spot — which is what happened on 07.09.
>
> **The file belongs in `~/Projects/wittypi/schedules/`.** Placed elsewhere it
> is not offered by menu item 6.

Verify what was actually written — the copy fails silently if `schedule.wpi` is
owned by root:

```bash
cat ~/Projects/wittypi/schedule.wpi
tail -5 ~/Projects/wittypi/wittyPi.log
```

The log states the computed transition times.

> [!TIP]
> If `schedule.wpi` is owned by root the copy fails silently and an old
> schedule stays active:
>
> ```bash
> sudo chown -R tobiask:tobiask ~/Projects/wittypi
> ```

`~/Projects/wittypi/wittyPi.log` states plainly why each transition happened —
scheduled, button, or interrupted.

---

## 15 · Presence detection

### Wiring

| Sensor | Pi pin | GPIO |
|---|---|---|
| 3V3 | **17** | — |
| GND | **9** | — |
| OT2 | **13** | GPIO 27 |
| Fan + | 1 (3.3 V) | — |
| Fan − | 6 | — |

> [!WARNING]
> **3.3 V, not 5 V.** Pin 2 destroys the sensor.
>
> The fan runs on 3.3 V deliberately: measured at 61 °C steady with
> `throttled=0x0`, and considerably quieter than on pin 4. Both share the
> 3.3 V rail.

TX and RX stay unconnected. TX would occupy GPIO 14, which the Witty Pi
monitors to detect shutdown. Sensor configuration happens separately over the
FT232 adapter at 115200 8N1.

```bash
watch -n 0.5 pinctrl get 27
```

`hi` in front of the sensor, `lo` out of range.

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

## 16 · Verification

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
| Temperature | around 61 °C steady, `vcgencmd get_throttled` returns `0x0` |

### Guest page over HTTP

```bash
KEY=$(node -e "console.log(require('$HOME/Projects/raspberrypi-magicmirror/config/secrets.js').remoteApiKey)")

curl -H "Authorization: apiKey $KEY" \
     "http://localhost:8080/api/notification/SHOW_HIDDEN_PAGE/gast"
```

> [!IMPORTANT]
> The API key goes in the **header**, not the URL, and the page name is a path
> segment. With a query string present, MMM-Remote-Control wraps the payload in
> an object and MMM-pages reports
> `Hidden page "[object Object]" does not exist!`

---

## 17 · Logging

MagicMirror writes to a file via journal:

```bash
journalctl -t magicmirror -b            # this boot only  ← use this by default
journalctl -t magicmirror -f -n 50      # follow live, with context
journalctl -t magicmirror -p err -b     # errors only
'''

> [!CAUTION]
> The log contains API tokens in URLs — the Genius token appears in full in
> every lyrics request. `logs/` must be gitignored.

<!-- TODO: logrotate -->

---

## Open items

**Documentation gaps:**

- [ ] Duration of `apt full-upgrade` (section 2)
- [ ] Duration and disk space of `npm install` (section 7)

**Improvements:**

- [ ] Commit pins in `modules.txt` — without them a rebuild in six months
      gets different code
- [ ] logrotate for `magicmirror.log` (section 17)
- [ ] `config.js.example` and `sync-config.sh` removed once `config.js` is
      tracked directly
- [ ] `mkdir -p "$MM_ROOT/logs"` into `bootstrap.sh`, and `node --check` on
      both patched files after the rewrite