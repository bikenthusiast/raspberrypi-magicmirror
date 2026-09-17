#!/usr/bin/env bash
#
# demo.sh — nimmt eine MagicMirror-Demo auf.
# AUSFÜHREN, NICHT SOURCEN:   bash demo.sh
#
# Ablauf: Enter → Aufnahme startet → Song von Hand starten →
#         Enter → QR-Code-Seite erscheint → 8 s → Ende.

set -uo pipefail          # bewusst ohne -e: ein Fehlschlag soll die Aufnahme nicht abbrechen

MM="$HOME/Projects/MagicMirror"
DEMO_DIR="$HOME/Projects/raspberrypi-magicmirror/demo"
OUT="$DEMO_DIR/demo_$(date +%F_%H-%M).mp4"

mkdir -p "$DEMO_DIR"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-[0-9] | head -1)")"

# --- API-Key lesen und pruefen -----------------------------------------
# Schluesselnamen an die eigene secrets.js anpassen!
RCKEY="$(node -e '
  const s = require("'"$MM"'/config/secrets.js");
  console.log(s.remoteControlApiKey);
')"

if [ -z "$RCKEY" ] || [ "$RCKEY" = "undefined" ]; then
  echo "FEHLER: API-Key nicht gefunden. Vorhandene Schluessel:" >&2
  node -e 'console.log(Object.keys(require("'"$MM"'/config/secrets.js")).join(", "))' >&2
  exit 1
fi
echo "API-Key gelesen (Laenge ${#RCKEY})."

# --- API-Aufruf, der sich meldet ---------------------------------------
api () {
  local resp code
  resp=$(curl -sS -w $'\n%{http_code}' -H "Authorization: apiKey $RCKEY" \
    "http://localhost:8080/api/notification/$1${2:+/$2}" 2>&1)
  code=$(tail -n1 <<<"$resp")
  echo "  api $1 ${2:-}  ->  HTTP $code  $(head -n -1 <<<"$resp" | tr -d '\n')" >&2
}

# --- Ausgangszustand ---------------------------------------------------
api LEAVE_HIDDEN_PAGE
echo
echo "Musik pausiert? Startbildschirm (Seite 0) sichtbar und ruhig?"
read -r -p "Dann Enter zum Aufnahmestart. " _

# --- Aufnahme ----------------------------------------------------------
wf-recorder -f "$OUT" -c libx264 -r 15 -F scale=1280:-2 &
REC=$!
trap 'kill -INT "$REC" 2>/dev/null' INT TERM

echo
echo "Aufnahme laeuft  ->  $OUT"
echo "Ein paar Sekunden Startbildschirm stehen lassen, dann Song starten."
read -r -p "Sobald die Lyrics stehen: Enter fuer die QR-Code-Seite. " _

api SHOW_HIDDEN_PAGE gast
sleep 8

kill -INT "$REC"
wait "$REC"
trap - INT TERM

echo
echo "fertig: $OUT"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" \
  | awk '{printf "Dauer: %.1f s\n", $1}'