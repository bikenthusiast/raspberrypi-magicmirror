# 012 · One global stylesheet after Apple's design guidelines: black glass, one typeface, colour from content

- **Status:** Proposed
- **Date:** 2026-10-25

## Context

The mirror is read in passing, from 1–2 m, through a two-way mirror in front of a 1440 × 2560 portrait
panel. Every lit pixel shines through the glass; black is mirror.

Each module brought its own look. MagicMirror's defaults set headers in 15 px uppercase with a rule,
the time in Roboto Thin, and dimmed text in `#666` (3.7:1 on black). MMM-MVG and the weather table used
16–17 px. Only the MMM-MyGCalendar fork had a mirror layout (28–52 px, light on black, no lit surfaces).
The Spotify page put a pale, lit card under the lyrics, the guest page a 14 px caption under the QR code.

Apple's Human Interface Guidelines were used as the yardstick: minimum sizes and contrast
(`accessibility.md`, `typography.md`), avoiding light weights for small text, colour reserved for
meaning (`color.md`), branding that defers to content (`branding.md`).

## Decision

`config/custom.css` sets one design system for every module, defined as CSS custom properties:

| Token | Value | Role |
|---|---|---|
| `--mirror-label` | `#f2f2f2`, 18.8:1 | primary text |
| `--mirror-label-2` | `#a3a3a3`, 8.3:1 | secondary text |
| `--mirror-label-3` | `#767676`, 4.6:1 | tertiary text, 28 px and up only |
| `--mirror-alert` | `#ff453a`, 6.2:1 | the only signal colour: "needs you" |
| type scale | 28 · 32 · 36 · 52 · 112 · 184 px | caption · rows · body · title · temperature · clock |
| typeface | Inter Variable (`fonts-inter-variable`) | the open counterpart to SF Pro |

Rules: no fills or cards behind content; no weight below 400; nothing below 28 px; colour only from
content (MVG line colours, calendar colours, weather icons, radar, album art). The clock is the one
large element, like a Lock Screen.

Config changes that go with it: no seconds on the clock, no "Wetter" header, dark base map for
MMM-RAIN-MAP (`invertColors`, greyed in CSS).

## Alternatives considered

| Option | Why not |
|---|---|
| SF Pro | Licensed for Apple platforms only; the Pi isn't one |
| Keep Roboto Condensed | MagicMirror's default; its Thin and Light cuts break up behind glass |
| Vendor the font into the repo | Debian ships Inter 4.1; one apt package is simpler than font files to symlink |
| Backdrop blur behind the now-playing card | On the Pi 4 it re-blurs the animated lyrics background every frame |
| Raise `--font-size` instead of the named sizes | MMM-LiveLyrics sizes itself in `em` from it and would grow uncontrolled |
| Restyle each module in its own stylesheet | Third-party modules are pinned upstream code; overrides belong in one place |

## Consequences

- One place for colours and sizes; the guest module and the calendar fork read the same tokens.
- Third-party CSS can change with a pin bump. The weekly module pull request is where a broken override
  shows up; `config/custom.css` selectors are grouped by module to make that check quick.
- Without `fonts-inter-variable` the mirror falls back to Roboto; `bootstrap.sh` warns.
- The larger type uses the space that was empty before. A running kitchen timer leaves about 70 px
  above the calendar; more rows in either would need a layout change, not smaller type.
