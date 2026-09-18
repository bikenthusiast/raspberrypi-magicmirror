# raspberrypi-magicmirror

A wall-mounted smart mirror built on MagicMirror², running on a Raspberry Pi 4B behind two-way mirror glass.
What makes it more than a dashboard is that the display reacts to state instead of rotating on a timer: it switches to the now-playing page by itself when music starts, holds a guest Wi-Fi page on request without disturbing the rotation, and puts the panel into standby when nobody is in front of it.

<p align="center">
  <img src="docs/demo/gif/demo_magicmirror_rot.gif" alt="The mirror switching from the idle page to the now-playing page when a song starts, then to the guest Wi-Fi page" width="420">
</p>
<p align="center"><em>Idle → now playing with live lyrics → guest Wi-Fi</em></p>

---

## The pages

| Idle — departures, weather & calendar | Idle — globe | Now playing | Guest Wi-Fi |
|:-------:|:-------:|:-------:|:-------:|
| <img src="docs/demo/screenshots/page0-calendar.png" alt="Departures, calendar, weather and rain radar" width="280"> | <img src="docs/demo/screenshots/page1-globe.png" alt="Departures, globe, weather and rain radar" width="280"> | <img src="docs/demo/screenshots/page2-spotify.png" alt="Now playing with cover art and live lyrics" width="280"> | <img src="docs/demo/screenshots/page-guest.png" alt="Guest Wi-Fi QR code" width="280"> |

Pages 0 and 1 rotate slowly while nothing is playing. Page 2 appears on its own when playback starts. The guest page is hidden and shown on request.

### How the pages are driven

`MMM-pages` only knows *which* modules belong to which page; its own timer is switched off. The custom
controller `MMM-SpotifyPages` decides *when* to switch:

| State | Page shown |
|---|---|
| Nothing playing | idle pages 0 ↔ 1, rotating every 5 minutes |
| Playback running | page 2 (player and lyrics), held for as long as the music plays |
| Playback paused or stopped | back to the idle rotation after a 30 s grace period (no jumping between tracks) |
| Hidden page active (guest Wi-Fi) | controller stays out of the way until the page is left or times out after 60 s |

Page switches are throttled, because a second switch during `MMM-pages`' fade animation can leave modules
locked and invisible. Details: [`docs/mmm-spotifypages.md`](docs/mmm-spotifypages.md).

Independently of MagicMirror, a 24 GHz mmWave radar puts the monitor into standby over HDMI-CEC after two
minutes without presence, and a Witty Pi 4 Mini powers the Pi down at night.

---

## Architecture

<p align="center">
  <img src="docs/architecture/magicmirror-architecture.svg" alt="Architecture: development on a Mac, GitHub as reference, the Raspberry Pi running MagicMirror under Electron as a systemd user service, the radar on GPIO, and the external services" width="420">
</p>

Custom modules live in this repository and are symlinked into the MagicMirror tree, so the
MagicMirror installation itself stays an unmodified upstream checkout. Third-party modules are cloned by
[`scripts/bootstrap.sh`](scripts/bootstrap.sh) from the manifest in [`modules.txt`](modules.txt).

Design decisions are recorded as ADRs in [`docs/adr/`](docs/adr/).

---

## Software stack

| Layer | Choice |
|---|---|
| OS | Raspberry Pi OS (Debian 13 "Trixie", arm64) |
| Display server | Wayland with the labwc compositor; `kanshi` for persistent rotation |
| Application | MagicMirror² 2.37 under Electron |
| Process management | systemd **user** service, logging to the journal |
| Display power | HDMI-CEC via `/dev/cec1`, driven by the presence sensor ([ADR-002](docs/adr/002-display-power-cec.md)) |
| Power schedule | Witty Pi 4 Mini, on 07:30 / off 22:15 ([ADR-005](docs/adr/005-power-management.md)) |

---

## Setup

Full installation, from a fresh Raspberry Pi OS image to a running mirror:
**[`docs/setup.md`](docs/setup.md)**

> [!IMPORTANT]
> **Credentials never belong in this repository.** `config/secrets.js` is git-ignored;
> [`config/secrets.example.js`](config/secrets.example.js) lists the required keys without values.
> A versioned pre-commit hook blocks common secret patterns — enable it once per clone with
> `git config core.hooksPath .githooks`. See [ADR-006](docs/adr/006-secrets-handling.md).

---

## Modules

### Own modules

| Module | Purpose |
|---|---|
| [`MMM-SpotifyPages`](modules/MMM-SpotifyPages/) | Invisible controller. Reads the playback state and drives `MMM-pages` as described above. |
| [`MMM-GuestWifi`](modules/MMM-GuestWifi/) | Renders a Wi-Fi QR code on a hidden page, so guests can join without being told the password. |

### Third-party modules

| Module | Purpose |
|---|---|
| [`MMM-pages`](https://github.com/edward-shen/MMM-pages) | Splits modules across pages and handles switching, including hidden pages. Its own rotation is disabled — `MMM-SpotifyPages` drives it. |
| [`MMM-MyGCalendar`](https://github.com/johnster000/MMM-MyGCalendar) | Calendar view against a private iCal feed, with keyword-based colour rules and a day modal. |
| [`MMM-OnSpotify`](https://github.com/Fabrizz/MMM-OnSpotify) | Playback state, cover art and device info from the Spotify Web API. Read-only scopes. |
| [`MMM-LiveLyrics`](https://github.com/Fabrizz/MMM-LiveLyrics) | Time-synced lyrics for the current track. |
| [`MMM-MVG`](https://github.com/KoblerS/MMM-MVG) | Live departures for the nearby Munich public transport stop. |
| [`MMM-OpenWeatherMapForecast`](https://github.com/MarcLandis/MMM-OpenWeatherMapForecast) | Current conditions and forecast (One Call API 3.0). |
| [`MMM-RAIN-MAP`](https://github.com/jalibu/MMM-RAIN-MAP) | Animated precipitation radar. |
| [`MMM-Globe`](https://github.com/LukeSkywalker92/MMM-Globe) | Rotating satellite view of the Earth. |
| [`MMM-Remote-Control`](https://github.com/Jopyth/MMM-Remote-Control) | HTTP API — used here to trigger the hidden page from outside. |

### Built in

`clock`, `newsfeed`, `alert` and `updatenotification` ship with MagicMirror² and need no separate
repository. They are configured as `fixed` in `MMM-pages`, so they stay visible across all pages.

---

## Guest Wi-Fi page

```bash
./scripts/guest-page.sh show    # show the QR code
./scripts/guest-page.sh hide    # back to the rotation (happens by itself after 60 s)
```

The script reads the API key from `config/secrets.js` and calls MMM-Remote-Control on `localhost:8080`.

---

## Documentation

| Document | Content |
|---|---|
| [`docs/setup.md`](docs/setup.md) | Rebuild from a blank SD card |
| [`docs/hardware.md`](docs/hardware.md) | Components, GPIO assignment, wiring, frame |
| [`docs/roadmap.md`](docs/roadmap.md) | Phases, status and what changed against the plan |
| [`docs/adr/`](docs/adr/) | Architecture decision records |
| [`docs/mmm-spotifypages.md`](docs/mmm-spotifypages.md) | The page controller in detail |
| [`docs/logging.md`](docs/logging.md) | Journal setup and log troubleshooting |
| [`docs/troubleshooting-spotifypages.md`](docs/troubleshooting-spotifypages.md) | Page locks and the Spotify token refresh loop |

---

## License

MIT — see [`LICENSE`](LICENSE). Third-party modules are cloned at install time and remain under their own
licenses; see the linked repositories.
