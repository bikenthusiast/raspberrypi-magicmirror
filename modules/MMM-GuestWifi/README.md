# MMM-GuestWifi

Custom module. Shows a QR code for the guest Wi-Fi — visitors scan it with
their camera app and are connected, without anyone having to read a password
out loud.

## Requirements

> [!IMPORTANT]
> **`qrencode` must be installed.** Without the package, `make-guest-qr.sh`
> aborts with:
>
> ```
> ERROR: qrencode is missing. Install with: sudo apt install qrencode
> ```

| Requirement | Installation | Purpose |
|---|---|---|
| `qrencode` | `sudo apt install qrencode` | generates the PNG file |
| `config/secrets.js` with credentials | see below | source for SSID and password |

On macOS the command is `brew install qrencode` — relevant if the code is
generated on the development machine and transferred over.

Nothing else. The module deliberately ships **no JavaScript dependency**.

## Why without a QR library

The previously used `uxigene/MMM-QRCode` generated the code at runtime in
the browser and broke on a version conflict:

```
Uncaught TypeError: QRCode.toCanvas is not a function
```

The module expected the API of the npm package `qrcode`, but a different
library ended up in the global namespace. Conflicts like this keep coming up
with loosely maintained modules that pin an open version range — `npm
install` then pulls in a newer major version with a changed API.

This module sidesteps the problem instead of solving it: the code is
generated once as a PNG with `qrencode`, and the module just displays the
image. There's no library left that could break.

Two further advantages:

**Escaping happens in exactly one place.** In the WIFI URI scheme, `\ ; , : "`
must be prefixed with a backslash. The shell handles that at generation time,
instead of it having to happen in JavaScript at runtime — where a literal
backslash needs to be doubled and the mistake only shows up once you try to
scan the code.

**The password never leaves the device.** `qrencode` works locally, unlike
the countless online generators.

## Setup

```bash
# Link the module
ln -sfn ~/Projects/raspberrypi-magicmirror/modules/MMM-GuestWifi \
        ~/Projects/MagicMirror/modules/MMM-GuestWifi

# Generate the QR code
cd ~/Projects/raspberrypi-magicmirror
./scripts/make-guest-qr.sh
```

The script reads its values from `config/secrets.js` (create it from the
`config/secrets.example.js` template if it doesn't exist yet):

| Key | Required | Meaning |
|---|---|---|
| `guestWifiSsid` | yes | network name, exactly as broadcast |
| `guestWifiPass` | yes, unless `guestWifiType` is `"nopass"` | password of the guest network |
| `guestWifiType` | no | `"WPA"` (default) or `"nopass"` for open networks |

For verification, the script also prints the code in the terminal. It can be
scanned directly with a phone — if it works there, a later problem lies with
the mirror's display, not with the encoded string.

Re-run the script after every change to SSID or password.

## Configuration

```js
{
    module: "MMM-GuestWifi",
    position: "top_left",
    header: "Gast-WLAN",
    config: {
        imageSize: 220
    }
}
```

| Option | Default | Meaning |
|---|---|---|
| `image` | `"guest-wifi.png"` | filename inside the module folder |
| `imageSize` | `220` | edge length in pixels |
| `ssid` | `""` | show the network name under the code. Leave empty to omit it |
| `caption` | `"Zum Verbinden scannen"` | caption text |

`ssid` is deliberately empty by default: on a wall mirror the network name
reveals more than some people would like — for a guest, the code is enough.

## Hidden page

In combination with MMM-pages, the module lives on a hidden page and is not
part of the rotation:

```js
hiddenPages: {
    gast: ["MMM-GuestWifi"]
}
```

### Show/hide script

```bash
./scripts/guest-page.sh show
./scripts/guest-page.sh hide
```

This calls the `/remote` route of MMM-Remote-Control, using the `remoteApiKey`
from `config/secrets.js`. `/remote` passes a plain-string payload through
as-is, which is what MMM-pages needs for `SHOW_HIDDEN_PAGE` — see below for
why that matters.

### Calling it from the browser console

```js
MM.getModules()[0].sendNotification("SHOW_HIDDEN_PAGE", "gast")
MM.getModules()[0].sendNotification("LEAVE_HIDDEN_PAGE")
```

Both return `undefined` — `sendNotification` has no return value. That's not
an error.

### Why not `/api/notification`

> [!IMPORTANT]
> **The API key must go in the header, not the URL** — and the page name
> `gast` is a path segment, not a query parameter.
>
> The reason is in `MMM-Remote-Control/API/api.js`:
>
> ```js
> 537   payload = request.params.p;
> 539   payload = {param: request.params.p, ...request.query};
> ```
>
> Line 537 passes the value straight through unwrapped — but only if the
> request has **no** query string. As soon as one is present, and
> `?apiKey=…` counts as one, line 539 kicks in and wraps it into an object.
> MMM-pages then looks for a page called `[object Object]`:
>
> ```
> [MMM-pages] Hidden page "[object Object]" does not exist!
> ```
>
> The same message shows up when passing it in the body. A bare string is
> also rejected by the body parser (`"gast" is not valid JSON`).
>
> Side effect of the header approach: the key doesn't end up in server logs
> or shell history.

`scripts/guest-page.sh` avoids this whole class of problem by using the
`/remote` route instead, which passes a plain string through regardless of
query parameters.

For notifications without a payload — `LEAVE_HIDDEN_PAGE`, for example —
`?apiKey=…` in the URL works fine too on `/api/notification`. The header is
still the better habit.

> [!NOTE]
> `MMM-SpotifyPages` controls the same page selection and knows nothing
> about the hidden page. A rotation step or a Spotify event will therefore
> hide the QR code again. To test, pause the rotation first:
>
> ```js
> m = MM.getModules().find(x => x.name === "MMM-SpotifyPages")
> m.stopRotation()
> ```

## Security

> [!CAUTION]
> **`guest-wifi.png` contains the Wi-Fi password** and belongs in
> `.gitignore`:
>
> ```gitignore
> modules/MMM-GuestWifi/guest-wifi.png
> ```
>
> The pre-commit hook checks text content and doesn't detect binary files.
> This line is therefore not optional.

The code is generated from `config/secrets.js`, which is also gitignored.
Neither the password nor anything it could be derived from lives in the
repository.

A permanently visible Wi-Fi code is acceptable for the guest network because
it's isolated from the main network. It would not be advisable for the main
network.

## Design

The white border around the code comes from the CSS and is functional: QR
codes need a bright quiet zone, otherwise many cameras fail to scan reliably
on a black background.

Error correction is set to level M. That's more forgiving of reflections in
the glass than the sparser level L, without making the code unnecessarily
dense.

## Troubleshooting

| Symptom | Cause |
|---|---|
| "QR-Code fehlt" in the module | `make-guest-qr.sh` wasn't run, or the symlink points nowhere |
| Old code shown despite regenerating | the cache buster should prevent this; otherwise hard-reload |
| Code scans but doesn't connect | SSID doesn't match character-for-character, or the encryption type is wrong |
| Code isn't recognized at all | too small — increase `imageSize` |

A check independent of the mirror:

```bash
qrencode -t ANSIUTF8 'WIFI:T:WPA;S:MeineSSID;P:meinPasswort;;'
```

If this code scans and the one on the mirror doesn't, the problem is the
display. If neither scans, the encoded string is wrong.
