# Changelog

All notable changes to this repository. Format after
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions after
[Semantic Versioning](https://semver.org/) as defined for this project in
[docs/cicd/releasing.md](docs/cicd/releasing.md): a **major** version changes how the mirror is
installed, wired or operated, a **minor** version adds a feature without a required step, a **patch**
fixes behaviour.

## [Unreleased]

### Added

- **Health check** `scripts/health-check.sh` with `systemd/health-check-user.timer`: once a minute it
  checks power (under-voltage flags), temperature, memory, disk, MagicMirror and internet (pinging the
  router as well, so an alert tells a Wi-Fi drop from a provider outage), logs the values
  to the journal and alerts on change, on the mirror and as an ntfy push to the phone. Restarts
  MagicMirror when systemd has given up on it ([docs/monitoring.md](docs/monitoring.md),
  [ADR-010](docs/adr/010-health-check-alerts.md))
- `config/secrets.example.js`: `healthNtfyTopic`, `healthNtfyServer` (optional; empty = no phone alerts)
- Hardware watchdog setup in [docs/monitoring.md](docs/monitoring.md#hardware-watchdog)
- **Reviewable updates** ([docs/updates.md](docs/updates.md), [ADR-011](docs/adr/011-reviewable-updates.md)):
  - `modules.txt` has a policy per module, `follow` or `hold`
  - `scripts/module-updates.sh` and the weekly workflow `module-updates.yml` move the `follow` pins and
    open a pull request listing the new commits and dependency changes
  - `scripts/setup-os-updates.sh` with `config/os/`: `unattended-upgrades` for Debian security updates
    only, apt timers inside the Witty Pi window
  - Health check: `os_updates=`, `sec=`, `reboot=` in every line; alerts when security updates stall for
    2 days and, phone only, when the manual OS update is 35 days overdue

- `scripts/witty-dst.sh` with `systemd/witty-dst*.timer`: keeps the Witty Pi schedule on local time
  across DST changes. After boot it re-syncs the RTC and moves `BEGIN` into the current offset (the
  schedule ran an hour off: off 21:15, on 06:30); on the evening before a switch it writes the wake-up
  in the RTC's old offset, which would otherwise wake two hours off
  ([docs/hardware.md](docs/hardware.md#daylight-saving-time))
- **Global stylesheet** `config/custom.css` after Apple's Human Interface Guidelines: black glass, Inter
  as the one typeface, three label greys from 18.8:1 to 4.6:1, nothing below 28 px, colour only from
  content. Linked by `bootstrap.sh`; a hand-made `custom.css` on the Pi is kept as
  `custom.css.local-<date>` ([ADR-012](docs/adr/012-visual-design.md)). Optional package:
  `fonts-inter-variable`, otherwise Roboto

### Changed

- Clock without seconds, weather without the "Wetter" header, rain map on a dark grey base map
- MMM-GuestWifi: caption 36 px instead of 14 px, QR code on `#f2f2f2` with rounded corners
- `deploy.sh` restarts MagicMirror when `config/custom.css` changes
- `deploy.sh` runs `bootstrap.sh` when `modules.txt` or `bootstrap.sh` changes (was a manual step) and
  restores the old pins on rollback
- `bootstrap.sh` fetches only modules whose pin is missing, runs `npm install` only where the commit
  changed, and exits non-zero when a patched file does not parse
- `updatenotification` disabled; removed from the `fixed` modules of MMM-pages

### Fixed

- Rain map stayed hidden in the rain after a visit to the Spotify or guest page: MMM-pages treated any
  module hidden at start-up as `hiddenOnStartup`. `bootstrap.sh` patches the check, MMM-pages is on
  `hold` ([docs/setup.md](docs/setup.md#what-the-mmm-pages-patch-does))

## [2.0.0] — YYYY-MM-DD

Camera-free gesture control and an automated path from commit to wall. Major version because
installation and operation change: new wiring and UART, new services, and the Pi becomes a deploy
target that pulls CI-approved commits instead of being edited in place.
**Upgrading from 1.0: [docs/upgrading-to-2.0.md](docs/upgrading-to-2.0.md).**

### Added

- **Gesture sensor** DFRobot SEN0628 (8×8 time-of-flight, no image data) on UART5
  ([ADR-007](docs/adr/007-gesture-sensor.md), [docs/sen0628.md](docs/sen0628.md)):
  driver `scripts/sen0628.py`, commissioning tools `tof_test.py`, `tof_bench.py`, `tof_rate.py`,
  recording tool `tof_record.py` (sessions in the git-ignored `data/`)
- **Swipe detector** `scripts/gesture.py` with `systemd/gesture.service`: swipe left shows the guest
  Wi-Fi page, swipe right hides it (`scripts/gesture-action.sh` → `guest-page.sh`). Replay of recordings,
  capture mode for missed and false detections, `--exec` hook
- **Edge bridge** `scripts/edge_bridge.py` with `systemd/edge-bridge.service`: gesture events from
  pi-edge-ai over MQTT open and close the guest page, with freshness, duplicate, source and rate checks
  ([ADR-008](docs/adr/008-edge-event-bridge.md))
- **CI** on GitHub Actions: gitleaks, shellcheck, ruff + pytest, JavaScript syntax, config loading and
  module tests ([docs/cicd/](docs/cicd/README.md))
- **CD**: `scripts/deploy.sh` with a systemd user timer pulls CI-green commits from `main`, restarts
  only what changed, smoke-tests and rolls back ([ADR-009](docs/adr/009-pull-based-deployment.md))
- **Tests**: edge bridge decisions against the producer's contract, hidden-page races with the real
  MMM-pages, swipe detector regression on 15 recorded takes
- Release process and version policy: [docs/cicd/releasing.md](docs/cicd/releasing.md)

### Changed

- `presence.service` addresses **`/dev/cec0`**: the display cable sits in HDMI0; `/dev/cec1` sent to
  an empty port
- `presence.py` treats unacknowledged CEC transmits and a missing physical address as failures instead
  of logging success while the display stays on
- `MMM-MyGCalendar` comes from the fork with the Today panel, pinned in `modules.txt` (d7db1d1);
  four calendar feeds, including a new *Kultur* calendar — `secrets.example.js` lists the keys
- `MMM-MVG` shows absolute departure times instead of minutes from now
- Fan moved to pin 4 (5 V) to relieve the 3.3 V rail; GPIO table and wiring docs updated
  ([docs/hardware.md](docs/hardware.md))
- Roadmap phase 5: camera replaced by the ToF sensor; CPU risk resolved

### Fixed

- Guest page stayed visible (or the calendar landed on top of it) after a quick show/hide:
  `MMM-SpotifyPages` re-asserts the page state once MMM-pages has settled
- `MMM-SpotifyPages` stayed paused after the automatic hidden-page timeout
- Shell and Python lint findings in `run-server.sh`, `demo-magicmirror.sh`, `presence.py`

### Known limitations

- At the target distance of 60–80 cm the rule-based detector recognises only about one swipe in five
  (reliable at 15–35 cm). A trained model from pi-edge-ai is planned for 2.1.0.
- After a reboot without a power cut the SEN0628 can stop answering; a full power-off recovers it.
- `gesture.service` and a sensor reader in pi-edge-ai must not run at the same time.
- The ToF sensor still sits on the bench; the frame cut-out is open.

## [1.0] — 2026-09-18

Base system, roadmap phases 1–4.

### Added

- MagicMirror² under Electron as a systemd user service, Wayland/labwc, portrait rotation via kanshi
- Guest Wi-Fi QR code on a hidden page, triggered through MMM-Remote-Control
  (`MMM-GuestWifi`, `guest-page.sh`, [ADR-001](docs/adr/001-hidden-page-trigger.md))
- Page control by Spotify playback (`MMM-SpotifyPages`)
- Presence detection with a 24 GHz mmWave radar on GPIO 27, display power via HDMI-CEC
  ([ADR-002](docs/adr/002-display-power-cec.md) – [ADR-004](docs/adr/004-sensor-connection.md))
- Witty Pi 4 Mini power schedule 07:30–22:15 ([ADR-005](docs/adr/005-power-management.md))
- Credentials in a git-ignored `secrets.js`, versioned pre-commit hook
  ([ADR-006](docs/adr/006-secrets-handling.md))
- Module manifest and `bootstrap.sh`, journal logging, setup and hardware documentation

[Unreleased]: https://github.com/bikenthusiast/raspberrypi-magicmirror/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/bikenthusiast/raspberrypi-magicmirror/compare/v1.0...v2.0.0
[1.0]: https://github.com/bikenthusiast/raspberrypi-magicmirror/releases/tag/v1.0
