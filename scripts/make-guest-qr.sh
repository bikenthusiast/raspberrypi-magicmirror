#!/usr/bin/env bash
#
# make-guest-qr.sh -- erzeugt den QR-Code fuer das Gast-WLAN
#
# Liest SSID und Passwort aus der .env und schreibt guest-wifi.png in den
# Modulordner. Der Code wird lokal erzeugt -- das Passwort verlaesst das
# Geraet nicht, anders als bei Online-Generatoren.
#
# Aufruf:  ./scripts/make-guest-qr.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$HOME/Projects/MagicMirror/.env}"
OUT="$REPO_ROOT/modules/MMM-GuestWifi/guest-wifi.png"

command -v qrencode >/dev/null 2>&1 || {
	echo "FEHLER: qrencode fehlt. Installation: sudo apt install qrencode" >&2
	exit 1
}

[[ -f "$ENV_FILE" ]] || {
	echo "FEHLER: $ENV_FILE nicht gefunden." >&2
	exit 1
}

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${GUEST_WIFI_SSID:?GUEST_WIFI_SSID fehlt in $ENV_FILE}"
: "${GUEST_WIFI_PASS:?GUEST_WIFI_PASS fehlt in $ENV_FILE}"

# Im WIFI-URI-Schema muessen \ ; , : " escaped werden.
esc() { printf '%s' "$1" | sed -e 's/[\\;,:"]/\\&/g'; }

SSID_ESC="$(esc "$GUEST_WIFI_SSID")"
PASS_ESC="$(esc "$GUEST_WIFI_PASS")"
TYPE="${GUEST_WIFI_TYPE:-WPA}"

PAYLOAD="WIFI:T:${TYPE};S:${SSID_ESC};P:${PASS_ESC};;"

mkdir -p "$(dirname "$OUT")"

# -s 8  Modulgroesse in Pixeln
# -m 2  Ruhezone, schmal -- der weisse Rahmen kommt per CSS
# -l M  Fehlerkorrektur mittel, gutmuetig bei Spiegelungen im Glas
qrencode -o "$OUT" -s 8 -m 2 -l M "$PAYLOAD"

echo "Erzeugt: $OUT"
echo "SSID:    $GUEST_WIFI_SSID"
echo
echo "Kontrolle im Terminal:"
qrencode -t ANSIUTF8 -m 1 "$PAYLOAD"