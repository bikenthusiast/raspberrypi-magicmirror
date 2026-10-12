#!/usr/bin/env bash
# gesture-action.sh -- what a recognised gesture does on the mirror
#
# Called by gesture.py (--exec) with the gesture name as the only argument.
# Edit the mapping below to change what each swipe triggers.
#
# Usage: ./scripts/gesture-action.sh SWIPE_LEFT|SWIPE_RIGHT
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "${1:-}" in
	SWIPE_LEFT)  "$REPO_ROOT/scripts/guest-page.sh" show ;;   # guest Wi-Fi QR code
	SWIPE_RIGHT) "$REPO_ROOT/scripts/guest-page.sh" hide ;;   # back to the rotation
	*) echo "unknown gesture: ${1:-<none>}" >&2; exit 1 ;;
esac
