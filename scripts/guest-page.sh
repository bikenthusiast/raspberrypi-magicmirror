#!/usr/bin/env bash
# guest-page.sh -- show or hide the guest Wi-Fi page
#
# Uses the /remote route of MMM-Remote-Control: it passes a plain-string
# payload through, which MMM-pages needs for SHOW_HIDDEN_PAGE.
# /api/notification always wraps the payload in an object and fails silently.
#
# Usage: ./scripts/guest-page.sh [show|hide]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY="$(node -p "require('$REPO_ROOT/config/secrets.js').remoteApiKey")"

send () {
	curl -fsS -G "http://localhost:8080/remote" \
		--data-urlencode "action=NOTIFICATION" \
		--data-urlencode "notification=$1" \
		${2:+--data-urlencode "payload=$2"} \
		--data-urlencode "apiKey=$KEY"
	echo
}

case "${1:-show}" in
	show) send SHOW_HIDDEN_PAGE gast ;;
	hide) send LEAVE_HIDDEN_PAGE ;;
	*)    echo "Usage: $0 [show|hide]" >&2; exit 1 ;;
esac
