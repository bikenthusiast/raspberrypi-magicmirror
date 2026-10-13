#!/usr/bin/env bash
#
# health-check.sh -- watch the Pi's vital signs and raise an alert on change
#
# Runs once a minute from health-check-user.timer. Every run logs one line to
# the journal; a check that goes bad (or recovers) also raises an alert:
#
#   - on the mirror, through MMM-Remote-Control and the default alert module
#   - on the phone, as an ntfy push, if healthNtfyTopic is set in secrets.js
#
# Alerts fire on state changes only: once when a check fails, once when it
# recovers. A check that stays bad does not repeat every minute.
#
# Usage:
#   scripts/health-check.sh             normal run (what the timer does)
#   scripts/health-check.sh --dry-run   print the checks, send nothing, keep no state
#   scripts/health-check.sh --test      send a test alert through both channels
#
# Read:
#   journalctl -t health -b                  every run of this boot
#   journalctl -t health -p warning -b       alerts and recoveries only
#
# Background: docs/monitoring.md and docs/adr/010-health-check-alerts.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- thresholds (override with environment variables) -------------------------
TEMP_MAX_C="${HEALTH_TEMP_MAX_C:-75}"            # the Pi 4 throttles at 80 °C
MEM_MIN_MB="${HEALTH_MEM_MIN_MB:-500}"           # MemAvailable
DISK_MAX_PCT="${HEALTH_DISK_MAX_PCT:-90}"        # root file system
PING_HOSTS="${HEALTH_PING_HOSTS:-1.1.1.1 9.9.9.9}"
MM_URL="${HEALTH_MM_URL:-http://localhost:8080}"
# Consecutive failed runs (= minutes) before a check raises an alert. Short
# outages -- a deployment restarting MagicMirror, a router reconnect -- stay quiet.
FAILS_MM="${HEALTH_FAILS_MM:-3}"
FAILS_NET="${HEALTH_FAILS_NET:-3}"
# A MagicMirror unit in "failed" state (systemd gave up restarting it) is
# started again, at most once per this many minutes. 0 disables it.
MM_RESTART_EVERY_MIN="${HEALTH_MM_RESTART_EVERY_MIN:-30}"
MIRROR_ALERT_MS="${HEALTH_MIRROR_ALERT_MS:-60000}"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/mirror-health"
HOST="$(hostname)"
MODE="run"

case "${1:-}" in
	"")        ;;
	--dry-run) MODE="dry-run" ;;
	--test)    MODE="test" ;;
	*)         echo "Usage: $0 [--dry-run|--test]" >&2; exit 2 ;;
esac

# --- output -------------------------------------------------------------------
#
# The <N> prefix sets the journal priority (sd-daemon(3)), so
# `journalctl -t health -p warning` shows alerts without the per-minute lines.
# systemd sets JOURNAL_STREAM; on a terminal the prefix is left out.
if [[ -n "${JOURNAL_STREAM:-}" ]]; then
	info () { echo "<6>$*"; }
	warn () { echo "<4>$*"; }
else
	info () { echo "$*"; }
	warn () { echo "$*"; }
fi

# --- secrets ------------------------------------------------------------------
#
# One node call for all three values. A missing or broken secrets.js only
# disables the alert channels; the checks and the journal line still run.
REMOTE_KEY=""
NTFY_TOPIC=""
NTFY_SERVER="https://ntfy.sh"
if secrets="$(node -e "
	const s = require('$REPO_ROOT/config/secrets.js');
	console.log(s.remoteApiKey || '');
	console.log(s.healthNtfyTopic || '');
	console.log(s.healthNtfyServer || 'https://ntfy.sh');
" 2>/dev/null)"; then
	{ read -r REMOTE_KEY; read -r NTFY_TOPIC; read -r NTFY_SERVER; } <<<"$secrets"
fi

# --- alert channels -----------------------------------------------------------

json_escape () {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	printf '%s' "$s"
}

# The /remote route, as in guest-page.sh. It parses a JSON payload into an
# object, which SHOW_ALERT needs. Fails quietly when MagicMirror is down --
# that case is reported by the phone channel and the journal.
alert_mirror () {
	local title="$1" message="$2"
	[[ -n "$REMOTE_KEY" ]] || return 0
	local payload
	payload="$(printf '{"type":"notification","title":"%s","message":"%s","timer":%s}' \
		"$(json_escape "$title")" "$(json_escape "$message")" "$MIRROR_ALERT_MS")"
	curl -fsS -m 5 -o /dev/null -G "$MM_URL/remote" \
		--data-urlencode "action=NOTIFICATION" \
		--data-urlencode "notification=SHOW_ALERT" \
		--data-urlencode "payload=$payload" \
		--data-urlencode "apiKey=$REMOTE_KEY" 2>/dev/null || true
}

# ntfy topics are public by name: anyone who knows the topic can read it.
# Hence the topic lives in secrets.js and should be long and random.
# HTTP header values must be ASCII, so titles avoid umlauts and the degree sign.
alert_phone () {
	local title="$1" message="$2" priority="$3" tags="$4"
	[[ -n "$NTFY_TOPIC" ]] || return 0
	curl -fsS -m 10 -o /dev/null \
		-H "Title: $title" -H "Priority: $priority" -H "Tags: $tags" \
		--data-binary "$message" "$NTFY_SERVER/$NTFY_TOPIC" 2>/dev/null || true
}

if [[ "$MODE" == "test" ]]; then
	[[ -n "$REMOTE_KEY" ]] || echo "remoteApiKey not set: no mirror alert" >&2
	[[ -n "$NTFY_TOPIC" ]] || echo "healthNtfyTopic not set: no phone alert" >&2
	alert_mirror "Health check" "Test alert from $HOST"
	alert_phone "$HOST: test" "Test alert from health-check.sh" default "test_tube"
	echo "test alert sent"
	exit 0
fi

# --- measurements -------------------------------------------------------------

throttled="unknown"
if command -v vcgencmd >/dev/null 2>&1; then
	throttled="$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)" || throttled="unknown"
fi

temp_c="unknown"
if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
	temp_c="$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))"
fi

mem_mb="$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)"
disk_pct="$(df --output=pcent / | tail -1 | tr -dc '0-9')"
mm_state="$(systemctl --user is-active magicmirror 2>/dev/null || true)"

net="down"
for h in $PING_HOSTS; do
	if ping -c 1 -W 3 "$h" >/dev/null 2>&1; then net="ok"; break; fi
done

info "health: throttled=$throttled temp=${temp_c}C mem_avail=${mem_mb}MB disk=${disk_pct}% mm=${mm_state:-unknown} net=$net"

# --- self-healing: MagicMirror ------------------------------------------------
#
# Restart=on-failure in the unit covers single crashes. After StartLimitBurst
# systemd stops trying and leaves the unit "failed" -- that case is picked up here.
mm_note=""
if [[ "$MODE" == "run" && "$mm_state" == "failed" && "$MM_RESTART_EVERY_MIN" -gt 0 ]]; then
	mkdir -p "$STATE_DIR"
	last=0
	[[ -f "$STATE_DIR/mm-restart" ]] && last="$(cat "$STATE_DIR/mm-restart")"
	now="$(date +%s)"
	if (( now - last >= MM_RESTART_EVERY_MIN * 60 )); then
		echo "$now" >"$STATE_DIR/mm-restart"
		systemctl --user reset-failed magicmirror || true
		if systemctl --user start magicmirror; then
			mm_note=" Restarted automatically."
		else
			mm_note=" Automatic restart failed."
		fi
		warn "health: magicmirror was failed, restart attempted.$mm_note"
	fi
fi

# --- evaluation ---------------------------------------------------------------
#
# State per check: "<consecutive fails> <first failure epoch> <alerted 0|1>".

check () {
	local name="$1" ok="$2" problem="$3" min_fails="$4" priority="${5:-high}"
	local fails=0 since=0 alerted=0 now
	now="$(date +%s)"

	if [[ "$MODE" == "dry-run" ]]; then
		if [[ "$ok" == "yes" ]]; then echo "  ok    $name"; else echo "  FAIL  $name: $problem"; fi
		return 0
	fi

	mkdir -p "$STATE_DIR"
	[[ -f "$STATE_DIR/$name" ]] && read -r fails since alerted <"$STATE_DIR/$name"

	if [[ "$ok" == "yes" ]]; then
		if [[ "$alerted" == "1" ]]; then
			local msg
			msg="$name OK again (problem since $(date -d "@$since" +%H:%M), $(( (now - since) / 60 )) min)"
			warn "health: RESOLVED $msg"
			alert_phone "$HOST: $name OK" "$msg" default "white_check_mark"
		fi
		echo "0 0 0" >"$STATE_DIR/$name"
		return 0
	fi

	fails=$(( fails + 1 ))
	(( since > 0 )) || since="$now"
	if (( fails >= min_fails )) && [[ "$alerted" == "0" ]]; then
		warn "health: ALERT $name: $problem"
		alert_mirror "Mirror: $name" "$problem"
		alert_phone "$HOST: $name" "$problem" "$priority" "warning"
		alerted=1
	fi
	echo "$fails $since $alerted" >"$STATE_DIR/$name"
}

[[ "$MODE" == "dry-run" ]] && echo "checks:"

# Power. get_throttled bit 0 = under-voltage now, bit 16 = since boot. Bit 16
# stays set until the next boot, so this alerts once per boot and reports
# "OK again" after a reboot without under-voltage.
if [[ "$throttled" =~ ^0x[0-9a-fA-F]+$ ]]; then
	t=$(( throttled ))
	if (( t & 0x1 )); then
		check power no "Under-voltage right now (throttled=$throttled). Check power supply and load." 1 urgent
	elif (( t & 0x10000 )); then
		check power no "Under-voltage occurred since boot (throttled=$throttled)." 1
	else
		check power yes "" 1
	fi
fi

if [[ "$temp_c" =~ ^[0-9]+$ ]]; then
	if (( temp_c >= TEMP_MAX_C )); then
		check temperature no "CPU at ${temp_c} °C (limit ${TEMP_MAX_C} °C). Fan running?" 2
	else
		check temperature yes "" 2
	fi
fi

if (( mem_mb < MEM_MIN_MB )); then
	check memory no "Only ${mem_mb} MB RAM available (limit ${MEM_MIN_MB} MB)." 2
else
	check memory yes "" 2
fi

if (( disk_pct >= DISK_MAX_PCT )); then
	check disk no "Root file system ${disk_pct}% full (limit ${DISK_MAX_PCT}%)." 1
else
	check disk yes "" 1
fi

if [[ "$mm_state" == "active" ]]; then
	check magicmirror yes "" "$FAILS_MM"
else
	check magicmirror no "magicmirror.service is ${mm_state:-unknown}.$mm_note Logs: journalctl -t magicmirror -b" "$FAILS_MM"
fi

# Phone alerts for this one cannot leave while the network is down. The
# "OK again" message afterwards carries the start time and the duration.
if [[ "$net" == "ok" ]]; then
	check network yes "" "$FAILS_NET"
else
	check network no "No internet: no reply from $PING_HOSTS." "$FAILS_NET"
fi
