#!/usr/bin/env bash
#
# witty-dst.sh -- keep the Witty Pi schedule on local time across DST changes
#
# Three things go wrong at a DST change without help (found 25.10.2026):
#
#  1. runScript.sh turns BEGIN into a timestamp with the UTC offset of the
#     BEGIN *date* and adds fixed 24 h cycles. A summer-time BEGIN keeps
#     meaning 07:30 CEST: in winter the mirror goes off at 21:15, on at 06:30.
#  2. The Witty Pi's RTC keeps plain wall-clock time and knows nothing about
#     DST. Across the switch night it still runs on the old offset, and the
#     Witty Pi software only rewrites it from the system clock when the RTC is
#     invalid or on request (menu item 1).
#  3. The wake-up alarm for the morning after the switch is written the day
#     before, as new-offset wall time, but compared against the RTC's old one:
#     two hours off (05:30 instead of 07:30 in autumn, 09:30 in spring).
#
# What this script does:
#
#   after boot (default)  switch NTP back on (the Witty Pi daemon turns it off
#                         at every boot when it copies the RTC to the system
#                         clock, `timedatectl set-ntp 0` in rtc_to_system), wait
#                         for the sync, then write the system time to the RTC
#                         if they differ by more than 10 s (fixes 2, and drift); move BEGIN to today if its UTC offset is
#                         not today's and re-run runScript.sh (fixes 1).
#   --evening             if the offset changes between now and the next
#                         startup (BEGIN's time of day, tomorrow), rewrite the
#                         startup alarm in the RTC's current offset, so it fires
#                         at the right local time (fixes 3). Otherwise nothing.
#   --check               report all three, change nothing.
#
# Run as root by systemd: witty-dst.timer 3 min after boot, and
# witty-dst-evening.timer daily at 22:00 (before the 22:15 shutdown). On the
# evening before a switch, wittyPi.sh then shows the startup in RTC time
# (e.g. "25 08:30:00" for 07:30 CET) -- that is intended. Assumes a daily schedule (ON + OFF =
# 24 h) whose switch-on time is BEGIN's time of day -- config/mirror.wpi.example.
#
# Background: docs/hardware.md (Daylight saving time), ADR-005.
set -euo pipefail

WITTY_DIR="${WITTY_DIR:-/home/tobiask/Projects/wittypi}"
SCHEDULE="$WITTY_DIR/schedule.wpi"
RTC_TOLERANCE=10
# Test hooks: a fixed "now" (epoch) and skipping the NTP wait.
now="${WITTY_DST_NOW:-$(date +%s)}"
ASSUME_NTP="${WITTY_DST_ASSUME_NTP:-0}"

mode="boot"
case "${1:-}" in
	"")        ;;
	--evening) mode="evening" ;;
	--check)   mode="check" ;;
	*)         echo "Usage: $0 [--evening|--check]" >&2; exit 2 ;;
esac

log () { echo "witty-dst: $*"; }

# Run a function from the Witty Pi's utilities.sh in a subshell, so its own
# log() and globals do not leak into this script.
witty () ( cd "$WITTY_DIR" && . ./utilities.sh >/dev/null 2>&1; "$@" )

offset_secs () {  # "+0100" -> 3600
	local z="$1" sign=1
	[[ "${z:0:1}" == "-" ]] && sign=-1
	echo $(( sign * (10#${z:1:2} * 3600 + 10#${z:3:2} * 60) ))
}

[[ -f "$SCHEDULE" ]] || { log "no $SCHEDULE -- nothing to do"; exit 0; }
if [[ "$mode" != "check" && $EUID -ne 0 ]]; then
	log "run with sudo (writes the RTC); --check works without"; exit 1
fi

# BEGIN line without comment: "BEGIN 2026-09-08 07:30:00"
read -r _ bdate btime < <(sed -n 's/#.*//; /^[[:space:]]*BEGIN[[:space:]]/{p;q}' "$SCHEDULE") || true
[[ "${bdate:-}" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ && "${btime:-}" =~ ^[0-2][0-9]:[0-5][0-9]:[0-5][0-9]$ ]] \
	|| { log "BEGIN not found or not 'YYYY-MM-DD HH:MM:SS' in $SCHEDULE"; exit 1; }

now_off="$(date -d "@$now" +%z)"

# --- 1. RTC against the system clock --------------------------------------------

sync_rtc () {
	if [[ "$ASSUME_NTP" != "1" ]]; then
		if [[ "$(timedatectl show -p NTP --value 2>/dev/null)" != "yes" ]]; then
			if [[ "$mode" == "check" ]]; then
				log "NTP is off (the Witty Pi daemon switches it off at boot) -- would switch it on"
			else
				log "NTP is off (the Witty Pi daemon switches it off at boot) -- switching it on"
				timedatectl set-ntp true
			fi
		fi
		if [[ "$mode" != "check" && "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" != "yes" ]]; then
			log "waiting up to 2 min for NTP to synchronise the system clock ..."
			local _
			for _ in $(seq 1 24); do
				[[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]] && break
				sleep 5
			done
		fi
		if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" != "yes" ]]; then
			log "system clock not NTP-synchronised -- leaving the RTC alone"
			return 0
		fi
		log "system clock NTP-synchronised"
		now="${WITTY_DST_NOW:-$(date +%s)}"
	fi
	local rtc sys delta
	rtc="$(witty get_rtc_timestamp 2>/dev/null || true)"
	[[ "$rtc" =~ ^[0-9]+$ ]] || { log "cannot read the RTC (I2C; run with sudo)"; return 0; }
	sys="$now"
	delta=$(( rtc - sys ))
	if (( ${delta#-} <= RTC_TOLERANCE )); then
		log "RTC matches the system clock (${delta}s)"
		return 0
	fi
	if [[ "$mode" == "check" ]]; then
		log "RTC is ${delta}s off the system clock -- would write system time to RTC"
		return 0
	fi
	log "RTC is ${delta}s off the system clock -- writing system time to RTC"
	witty system_to_rtc >/dev/null
	return 10
}

# --- 2. BEGIN in today's UTC offset ----------------------------------------------

fix_begin () {
	local begin_off today new
	begin_off="$(date -d "$bdate $btime" +%z)"
	if [[ "$begin_off" == "$now_off" ]]; then
		log "BEGIN $bdate $btime has today's UTC offset ($now_off)"
		return 0
	fi
	today="$(date -d "@$now" +%F)"
	if [[ "$mode" == "check" ]]; then
		log "BEGIN $bdate $btime is UTC$begin_off, today UTC$now_off -- would move it to $today"
		return 0
	fi
	# Rewrite in place, not with sed -i: a new file would belong to root, and
	# the Witty Pi menu then silently fails to copy schedules over it.
	new="$(sed -E "s/^([[:space:]]*BEGIN[[:space:]]+)$bdate([[:space:]]+$btime)/\\1$today\\2/" "$SCHEDULE")"
	printf '%s\n' "$new" >"$SCHEDULE"
	grep -qE "^[[:space:]]*BEGIN[[:space:]]+${today}[[:space:]]+${btime}" "$SCHEDULE" \
		|| { log "could not rewrite BEGIN in $SCHEDULE"; exit 1; }
	log "BEGIN $bdate $btime (UTC$begin_off) -> $today $btime (UTC$now_off)"
	bdate="$today"
	return 10
}

reschedule () {
	local out
	# Same call as the Witty Pi daemon at boot, without "revise".
	out="$(cd "$WITTY_DIR" && ./runScript.sh 0 2>&1 | tee -a "$WITTY_DIR/schedule.log")"
	grep -E "Schedule next (shutdown|startup)" <<<"$out" | sed 's/^.*Schedule/witty-dst:   schedule/' || true
	grep -qE "Schedule next shutdown" <<<"$out" \
		|| { log "runScript.sh did not schedule a shutdown -- check $WITTY_DIR/schedule.log"; exit 1; }
}

# --- 3. Startup alarm across tonight's switch -------------------------------------

fix_startup_alarm () {
	local day target target_off want have
	# Next switch-on: BEGIN's time of day, today if still ahead, else tomorrow.
	day="$(date -d "@$now" +%F)"
	target="$(date -d "$day $btime" +%s)"
	if (( target <= now )); then
		day="$(date -u -d "@$(( $(date -u -d "$day" +%s) + 86400 ))" +%F)"
		target="$(date -d "$day $btime" +%s)"
	fi
	target_off="$(date -d "@$target" +%z)"
	if [[ "$target_off" == "$now_off" ]]; then
		log "no DST change before the next startup ($(date -d "@$target" '+%a %H:%M'))"
		return 0
	fi
	# The RTC runs on the current offset until the next boot rewrites it, so
	# express the target in that offset: autumn 07:30 CET -> 08:30, spring
	# 07:30 CEST -> 06:30.
	want="$(date -u -d "@$(( target + $(offset_secs "$now_off") ))" '+%d %H:%M:%S')"
	have="$(witty get_startup_time 2>/dev/null || true)"
	[[ -n "$have" ]] || { log "cannot read the startup alarm (I2C; run with sudo)"; [[ "$mode" == "check" ]] && return 0; exit 1; }
	log "DST change before the next startup ($now_off -> $target_off): startup $(date -d "@$target" '+%a %d.%m. %H:%M') local = RTC alarm $want (set: $have)"
	if [[ "$have" == "$want" ]]; then
		return 0
	fi
	if [[ "$mode" == "check" ]]; then
		log "would set the startup alarm to $want"
		return 0
	fi
	# shellcheck disable=SC2046  # day hour minute second as four arguments
	witty set_startup_time $(tr ': ' '  ' <<<"$want")
	have="$(witty get_startup_time)"
	[[ "$have" == "$want" ]] || { log "startup alarm reads back as $have, not $want"; exit 1; }
	log "startup alarm set to $want"
}

# --- main ------------------------------------------------------------------------

changed=0
case "$mode" in
	boot)
		sync_rtc || changed=1
		fix_begin || changed=1
		if (( changed )); then reschedule; else log "schedule unchanged"; fi
		;;
	evening)
		fix_startup_alarm
		;;
	check)
		sync_rtc || true
		fix_begin || true
		fix_startup_alarm
		;;
esac
