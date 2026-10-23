#!/usr/bin/env bash
# gesture-action.sh -- what a recognised gesture does on the mirror
#
# Called by gesture.py (--exec) with the gesture name as the only argument.
# Edit the mapping below to change what each gesture triggers.
#
# Usage: ./scripts/gesture-action.sh SWIPE_LEFT|SWIPE_RIGHT|PUSH|PULL
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Dyson lamp control via the keep-warm daemon (dyson-lamp-ble, examples/mirror).
# Adjust these two paths to your checkout of the dyson_lamp repo if it differs.
LAMP_PY="$HOME/Projects/dyson_lamp/.venv/bin/python"
LAMP_CTL="$HOME/Projects/dyson_lamp/examples/mirror/lampctl.py"
# Must match the daemon's socket (dyson-lampd.service sets the same path). This
# service has no XDG_RUNTIME_DIR, so pin it explicitly instead of defaulting to it.
export DYSON_LAMP_SOCK="$HOME/.cache/dyson_lamp/dyson-lamp.sock"

# Immediate audible feedback that a gesture was recognised, independent of how
# long the lamp itself takes (cold BLE connect can be ~10 s). Non-blocking.
# Audio runs in the user's PipeWire/Pulse session, which lives under the user
# runtime dir — this (system) service has no XDG_RUNTIME_DIR, so pin it.
SOUNDS="$HOME/Projects/dyson_lamp/examples/mirror/sounds"
beep() {
	local f="$SOUNDS/$1"
	[ -r "$f" ] || return 0
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
		sh -c 'for p in pw-play paplay aplay; do command -v "$p" >/dev/null 2>&1 && exec "$p" "$0"; done' "$f" 2>/dev/null &
}

lamp() {
	if [ -x "$LAMP_PY" ]; then
		"$LAMP_PY" "$LAMP_CTL" "$1" || echo "lamp: ctl $1 failed (daemon running?)" >&2
	else
		echo "lamp: $LAMP_PY not found" >&2
	fi
}

case "${1:-}" in
	SWIPE_LEFT)  "$REPO_ROOT/scripts/guest-page.sh" show ;;   # guest Wi-Fi QR code
	SWIPE_RIGHT) "$REPO_ROOT/scripts/guest-page.sh" hide ;;   # back to the rotation
	PUSH)        beep on.wav;  lamp on  ;;   # hand toward the mirror  -> lamp on (synchronised)
	PULL)        beep off.wav; lamp off ;;   # hand away from the mirror -> lamp off
	*) echo "unknown gesture: ${1:-<none>}" >&2; exit 1 ;;
esac
