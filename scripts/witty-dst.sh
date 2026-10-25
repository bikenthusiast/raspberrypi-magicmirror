#!/usr/bin/env bash
#
# witty-dst.sh -- keep the Witty Pi schedule on local time across DST changes
#
# The Witty Pi's runScript.sh turns BEGIN into a Unix timestamp with the UTC
# offset of the BEGIN *date* and then adds fixed 24 h cycles. A BEGIN in
# summer time therefore means "07:30 CEST" for ever: after the switch to
# winter time the mirror goes off at 21:15 and on at 06:30 (seen 25.10.2026),
# and the other way round in spring.
#
# This script compares the UTC offset of BEGIN with today's. If they differ,
# it moves BEGIN to today's date (same time of day) and runs runScript.sh
# again, which writes the corrected next shutdown and startup to the RTC.
# Otherwise it changes nothing. BEGIN today is safe either way: before 07:30
# runScript.sh starts the cycle at BEGIN (shutdown tonight, startup tomorrow),
# after 07:30 it is in the ON phase until tonight's shutdown.
#
# Run as root by witty-dst.timer a few minutes after every boot, after the
# Witty Pi daemon has scheduled with the old BEGIN. Limitation: on the morning
# of the switch itself the Pi still wakes at the old time (06:30 in autumn,
# 08:30 in spring), because that alarm was set the evening before.
#
# Usage:
#   sudo scripts/witty-dst.sh            fix if needed
#   scripts/witty-dst.sh --check         report only, change nothing
#
# Background: docs/hardware.md (Witty Pi), ADR-005.
set -euo pipefail

WITTY_DIR="${WITTY_DIR:-/home/tobiask/Projects/wittypi}"
SCHEDULE="$WITTY_DIR/schedule.wpi"
check_only=0
case "${1:-}" in
	"")      ;;
	--check) check_only=1 ;;
	*)       echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

log () { echo "witty-dst: $*"; }

[[ -f "$SCHEDULE" ]] || { log "no $SCHEDULE -- nothing to do"; exit 0; }

# BEGIN line without comment: "BEGIN 2026-09-08 07:30:00"
read -r _ bdate btime < <(sed -n 's/#.*//; /^[[:space:]]*BEGIN[[:space:]]/{p;q}' "$SCHEDULE") || true
[[ "${bdate:-}" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ && "${btime:-}" =~ ^[0-2][0-9]:[0-5][0-9]:[0-5][0-9]$ ]] \
	|| { log "BEGIN not found or not 'YYYY-MM-DD HH:MM:SS' in $SCHEDULE"; exit 1; }

begin_off="$(date -d "$bdate $btime" +%z)"
now_off="$(date +%z)"
if [[ "$begin_off" == "$now_off" ]]; then
	log "BEGIN $bdate $btime has today's UTC offset ($now_off) -- schedule is on local time"
	exit 0
fi

today="$(date +%F)"
log "BEGIN $bdate $btime is UTC$begin_off, today is UTC$now_off -- the schedule is off by an hour"
if (( check_only )); then
	log "would move BEGIN to $today $btime and re-run runScript.sh (run with sudo to fix)"
	exit 0
fi
[[ $EUID -eq 0 ]] || { log "run with sudo (runScript.sh writes the RTC)"; exit 1; }

# Rewrite in place, not with sed -i: a new file would belong to root, and the
# Witty Pi menu then silently fails to copy schedules over it (docs/setup.md).
new="$(sed -E "s/^([[:space:]]*BEGIN[[:space:]]+)$bdate([[:space:]]+$btime)/\\1$today\\2/" "$SCHEDULE")"
printf '%s\n' "$new" >"$SCHEDULE"
grep -qE "^[[:space:]]*BEGIN[[:space:]]+${today}[[:space:]]+${btime}" "$SCHEDULE" \
	|| { log "could not rewrite BEGIN in $SCHEDULE"; exit 1; }
log "BEGIN -> $today $btime"

# Same call as the Witty Pi daemon at boot, without "revise".
out="$("$WITTY_DIR/runScript.sh" 0 2>&1 | tee -a "$WITTY_DIR/schedule.log")"
grep -E "Schedule next (shutdown|startup)" <<<"$out" | sed 's/^/witty-dst:   /' || true
grep -qE "Schedule next shutdown" <<<"$out" || { log "runScript.sh did not schedule a shutdown -- check $WITTY_DIR/schedule.log"; exit 1; }
