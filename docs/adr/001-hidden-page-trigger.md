# 001 · Hidden pages are triggered by notification through MMM-Remote-Control

- **Status:** Accepted
- **Date:** 2026-09-04 (roadmap phase 1)

## Context

The guest Wi-Fi QR code should appear on request and not be part of the page rotation. Later phases
(presence detection, gestures) need the same thing: something outside MagicMirror asks for a page to
appear or disappear. Building the trigger first means those phases only have to answer *who* presses
it.

Visibility of modules is owned by `MMM-pages`, which tracks it with lock strings. Hiding or showing
modules directly from outside competes with those locks — a module shown by someone else can be left
locked and invisible by `MMM-pages` later.

## Decision

The QR code lives on an `MMM-pages` **hidden page** (`hiddenPages: { gast: [...] }`). It is opened
and closed with the `MMM-pages` notifications `SHOW_HIDDEN_PAGE` / `LEAVE_HIDDEN_PAGE`, sent through
the HTTP API of `MMM-Remote-Control`. [`scripts/guest-page.sh`](../../scripts/guest-page.sh) wraps the
call. The page controller `MMM-SpotifyPages` pauses all switching while a hidden page is open and
closes it itself after `hiddenPageTimeoutMs`.

## Alternatives considered

| Option | Why not |
|---|---|
| `hide()`/`show()` on the module directly | Bypasses `MMM-pages`' locks; the rotation would hide the code again or leave modules locked |
| QR code as a regular page in the rotation | Shows the guest code to everyone passing by, all day |
| Separate web page on the Pi | Guests would need to reach the Pi first — the problem the QR code is meant to solve |

## Consequences

- One mechanism for every future trigger: radar, gesture or phone all end in the same notification.
- The payload must reach `MMM-pages` as a plain string. `/api/notification` with a query string wraps
  it in an object, and `MMM-pages` then reports `Hidden page "[object Object]" does not exist!` — a
  silent failure from the caller's point of view. `guest-page.sh` uses the `/remote` route, which
  passes the string through.
- `MMM-Remote-Control` listens on loopback only (`ipWhitelist`) and requires an API key from
  `secrets.js`; external triggers have to run on the Pi.
