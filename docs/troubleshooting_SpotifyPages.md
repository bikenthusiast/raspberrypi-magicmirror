# Troubleshooting — page locks and Spotify tokens

Two failure modes found on 05.09.2026. Both look like something is broken
elsewhere, and both have a clear mechanism.

---

## Blank screen except the clock

### Symptom

After a page change — typically when leaving the Spotify page — most modules
disappear. Only the clock remains, because it renders purely in the browser and
is unaffected by MMM-pages.

The current page is correct, and the modules are loaded. They are simply held
hidden.

### Diagnosis

```js
MM.getModules().find(x => x.name === "MMM-MVG").hidden
```

`true` while the module is on the current page is the contradiction. Then check
who is holding it:

```js
MM.getModules().find(x => x.name === "MMM-MVG").lockStrings
```

A value like `['module_14_MMM-pages']` confirms it: MMM-pages set a lock and
never released it.

### Cause

MMM-pages fades modules out and back in using `setTimeout`. If a second page
change arrives while that animation is still running, the release for the
previous page can be lost. The modules stay locked and remain invisible even
though the page state itself is correct.

It shows up most often when leaving the Spotify page, because the switch back
and the first rotation step follow each other closely.

### Recovery

```js
MM.getModules().forEach(x => x.show(0, {lockString: "module_14_MMM-pages"}))
```

The lock string must be passed. In MagicMirror a lock can only be cleared by
whoever set it — omitting it does nothing.

Reloading the page works too.

### Prevention

`MMM-SpotifyPages` v8 throttles page changes: no two `PAGE_SELECT` messages are
sent closer together than `minSwitchGapMs` (default 700 ms). A change that
arrives too early is delayed, and a delayed change that is superseded gets
discarded — only the most recent target state is sent.

Verify the version actually deployed:

```bash
grep -c "minSwitchGapMs" ~/Projects/MagicMirror/modules/MMM-SpotifyPages/MMM-SpotifyPages.js
```

`0` means an older version is in place and the problem will recur.

If locks still occur with v8, raise `minSwitchGapMs`. MMM-pages has its own
animation duration, and it may exceed 700 ms.

---

## Spotify playback no longer detected after several hours

### Symptom

Everything works for hours, then playback stops being recognised. The mirror
keeps rotating the idle pages while music is playing. Waiting does not help; a
server restart fixes it immediately.

### Diagnosis

```js
s = MM.getModules().find(x => x.name === "MMM-OnSpotify")
s.lastStatus
```

If this reports `isEmpty*` while music is playing, MMM-OnSpotify itself has
lost contact with Spotify — the page controller is working correctly on stale
input.

In the log:

```bash
grep -i "onspotify" ~/Projects/MagicMirror/logs/mm_*.log \
  | grep -iE "token|refresh|CODE|error"
```

Look at what follows the last successful `Access token expiration` line.

### Cause

In `utils/SpotifyFetcher.js`, `getData()` refreshes the access token once it
has expired. On success it updates `tokenExpiresAt`. **On failure it does
not.**

That means the next poll sees an expired token again and immediately attempts
another refresh. There is no backoff and no retry limit — the refresh rate
equals the poll rate.

A single transient `429` therefore puts the module into a loop: it hammers
Spotify's token endpoint once per poll interval, Spotify throttles harder, the
refresh keeps failing. It cannot recover on its own.

A restart clears it because the downtime lets the rate-limit window expire.

### Mitigation

Raise the poll intervals in the MMM-OnSpotify config. Values are in seconds:

```js
isPlaying: 5,
isEmpty: 10,
isPlayingHidden: 10,
isEmptyHidden: 30,
```

This cuts request volume by roughly 80 percent — both the baseline load that
triggers the `429` and the retry rate once one occurs. For a mirror, a track
title updating every 5 seconds instead of every second is imperceptible.

The `Hidden` variants apply while MMM-pages keeps the module hidden. Since the
Spotify page is only shown part of the time, generous values there cost
nothing.

> [!IMPORTANT]
> Do not add an `events` block to the MMM-OnSpotify config. MagicMirror merges
> config objects flatly, so a custom `events` object replaces the module's
> defaults entirely. Dropping `LIVELYRICS_NOTICE` breaks the handshake with
> MMM-LiveLyrics, which then shows "MMM-OnSpotify not found".

### Also check for a second instance

Two MagicMirror processes sharing one set of credentials double every request:

```bash
ss -ltnp | grep 8080
ps aux | grep -c "[n]ode.*MagicMirror"
```

### Structural mitigation

The Witty Pi schedule (on 7:30, off 22:15) caps runtime below 15 hours, which
is under the point where the failure has been observed. Combined with the
longer intervals this may be enough.

If it still occurs, restarting the **MagicMirror process** around midday is the
pragmatic patch — roughly 20 seconds of downtime, versus about two minutes for
a full Pi reboot.

---

## Rate limiting: CODE 429

### Symptom

```
[WARN] [MMM-OnSpotify] Player data >> CODE 429
You are being rate limited by Spotify (429).
Use only one SpotifyApp per module/implementation
```

Playback detection drops out briefly, then recovers.

### Assessment

Not a module fault. Spotify is throttling. It resolves on its own.

Common triggers: several server restarts in quick succession, a second
MagicMirror instance using the same credentials, or poll intervals set too
aggressively.

Relevant because a `429` landing on a token refresh is what starts the loop
described above.

---

## Upcoming: refresh tokens expire after six months

Spotify announced on 18 June 2026 that refresh tokens issued through the
Authorization Code flow will expire after six months, effective 20 July 2026.

For a module that keeps the refresh token in its config, this means
re-authorising roughly twice a year. Worth noting now so the symptom is
recognisable later: authentication simply stops working and no restart helps.