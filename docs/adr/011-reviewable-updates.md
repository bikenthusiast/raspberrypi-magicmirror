# 011 · Updates arrive as reviewable changes: module pins by pull request, OS security updates only

- **Status:** Proposed
- **Date:** 2026-10-23

## Context

The mirror shows two kinds of update notices: MagicMirror's `updatenotification` module (e.g. for
MMM-RAIN-MAP and MMM-Remote-Control) and the desktop's update popup at boot. Neither says what changed,
and acting on them means editing the Pi by hand — which ADR-009 replaced with CI-gated deployment.

Since October 2026 every third-party module is pinned in `modules.txt`, so a rebuild is reproducible. But
pins only age: upstream fixes (MMM-RAIN-MAP's data source, MMM-OnSpotify issue #116) never arrive unless
someone moves them. Not every module may move: MMM-MyGCalendar is an own fork, MMM-OnSpotify and
MMM-LiveLyrics are patched by `bootstrap.sh`, and MMM-Globe's upstream does not fix its dead image URLs.

The Pi runs 07:30–22:15 (Witty Pi, ADR-005) and is power-cycled every night. Its fragile parts — UART5 for
the gesture sensor, CEC standby, labwc output handling — depend on the kernel, firmware and compositor
from the Raspberry Pi archive. The code runs next to credentials (`secrets.js`), so third-party code should
not change unseen.

## Decision

**Modules:** `modules.txt` gets a policy per module, `follow` or `hold`. A weekly GitHub workflow moves the
`follow` pins to upstream's head and opens one pull request listing the new commits and dependency changes.
Merging it is the review; `deploy.sh` then runs `bootstrap.sh` and rolls back to the old pins if MagicMirror
does not come up. `updatenotification` is disabled.

**OS:** `unattended-upgrades` installs Debian security updates daily, nothing else, without rebooting.
Everything else waits for a monthly `apt full-upgrade` by hand. The health check reports pending updates
and alerts when security updates stall (2 days) or the manual update is overdue (35 days).

## Alternatives considered

| Option | Why not |
|---|---|
| `updatenotification` with its `updates` option (auto `git pull`) | Moves modules past their pins: `modules.txt` no longer describes the Pi, a rollback cannot restore the old state, and nobody sees the change before it runs |
| Dependabot / Renovate | Neither understands a plain-text manifest of git URLs and commits; Renovate's regex manager could, but brings a hosted app and its configuration for eleven lines |
| Auto-merge the module PR when CI is green | CI checks this repository's code, not the third-party modules; the merge is the only point where a human looks at them |
| `unattended-upgrades` for all origins | Would install kernel, firmware and labwc updates unseen, and the nightly power cycle would activate them the next morning — on the parts this setup depends on most (UART5, CEC, labwc) |
| No automatic OS updates | Security fixes (OpenSSL, system libraries) would wait up to a month on a device that is always on the network |

## Consequences

- One PR per week at most, only when something moved. Merging stays a deliberate act.
- `deploy.sh` runs `bootstrap.sh` (network, `npm install`) when `modules.txt` changes; such a deploy takes
  minutes instead of seconds. A rollback needs the network as well.
- The smoke test catches a MagicMirror that does not start, not a module that renders wrongly. The deploy
  log counts MagicMirror `ERROR` lines after a module update as a pointer.
- PRs from the workflow are created with `GITHUB_TOKEN`, which does not trigger CI; the workflow starts CI
  explicitly (`workflow_dispatch`). The repository setting *Allow GitHub Actions to create pull requests*
  must be on.
- The OS gets security fixes within a day; the rest needs the monthly routine in `docs/updates.md`, with a
  reminder when it is skipped.
