#!/usr/bin/env bash
#
# make-guest-qr.sh -- generate the guest WiFi QR code
#
# Reads SSID and password from config/secrets.js and writes
# guest-wifi.png into the MMM-GuestWifi module folder.
#
# The code is generated locally, so the password never leaves the
# machine -- unlike the many online QR generators.
#
# Usage:
#     ./scripts/make-guest-qr.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS="${SECRETS:-$REPO_ROOT/config/secrets.js}"
OUT="$REPO_ROOT/modules/MMM-GuestWifi/guest-wifi.png"

command -v qrencode >/dev/null 2>&1 || {
	echo "ERROR: qrencode is missing. Install with: sudo apt install qrencode" >&2
	exit 1
}

command -v node >/dev/null 2>&1 || {
	echo "ERROR: node is missing." >&2
	exit 1
}

[[ -f "$SECRETS" ]] || {
	echo "ERROR: $SECRETS not found." >&2
	echo "Template: cp config/secrets.example.js config/secrets.js" >&2
	exit 1
}

# Reading through node rather than grep: secrets.js is JavaScript, so
# quoting, comments and trailing commas are node's problem, not ours.
read_secret () {
	node -e "
		const s = require('$SECRETS');
		process.stdout.write(String(s.$1 ?? ''));
	" 2>/dev/null
}

SSID="$(read_secret guestWifiSsid)"
PASS="$(read_secret guestWifiPass)"
TYPE="$(read_secret guestWifiType)"
TYPE="${TYPE:-WPA}"

[[ -n "$SSID" ]] || {
	echo "ERROR: guestWifiSsid is empty in $SECRETS" >&2
	exit 1
}

if [[ "$TYPE" != "nopass" && -z "$PASS" ]]; then
	echo "ERROR: guestWifiPass is empty in $SECRETS" >&2
	echo "       Set guestWifiType to 'nopass' for an open network." >&2
	exit 1
fi

# In the WIFI URI scheme the characters \ ; , : " must be escaped.
# Doing it here means it happens once, in one place -- rather than at
# runtime in JavaScript, where a literal backslash needs doubling and
# the mistake only shows up when the code refuses to connect.
esc () {
	printf '%s' "$1" | sed -e 's/[\\;,:"]/\\&/g'
}

SSID_ESC="$(esc "$SSID")"

if [[ "$TYPE" == "nopass" ]]; then
	PAYLOAD="WIFI:T:nopass;S:${SSID_ESC};;"
else
	PAYLOAD="WIFI:T:${TYPE};S:${SSID_ESC};P:$(esc "$PASS");;"
fi

mkdir -p "$(dirname "$OUT")"

# -s 8  module size in pixels
# -m 2  narrow quiet zone -- the white border comes from CSS
# -l M  medium error correction, forgiving of reflections in the glass
qrencode -o "$OUT" -s 8 -m 2 -l M "$PAYLOAD"

echo "Written: $OUT"
echo "SSID:    $SSID"
echo "Type:    $TYPE"
echo
echo "Scan this to verify before trusting the mirror:"
qrencode -t ANSIUTF8 -m 1 "$PAYLOAD"
