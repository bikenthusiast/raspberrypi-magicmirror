#!/usr/bin/env bash
#
# run-server.sh -- starts MagicMirror in server mode and logs to a file
# whose name carries both the start and the end timestamp.
#
# While running, the file is called
#     mm_2026-09-05_143012_running.log
# and on exit it is renamed to
#     mm_2026-09-05_143012__2026-09-05_221530.log
#
# The end timestamp is only known once the process stops, hence the
# detour via a provisional name plus a trap on EXIT.
#
# Usage:
#     ./scripts/run-server.sh
#
# Environment variables:
#     MM_ROOT     path to MagicMirror (default ~/Projects/MagicMirror)
#     LOG_DIR     where logs are kept  (default $MM_ROOT/logs)
#     KEEP_LOGS   number of logs to retain (default 20, 0 = keep all)
#
set -uo pipefail

MM_ROOT="${MM_ROOT:-$HOME/Projects/MagicMirror}"
LOG_DIR="${LOG_DIR:-$MM_ROOT/logs}"
KEEP_LOGS="${KEEP_LOGS:-20}"

[[ -d "$MM_ROOT" ]] || {
	echo "ERROR: $MM_ROOT not found." >&2
	exit 1
}

mkdir -p "$LOG_DIR"

START="$(date +%Y-%m-%d_%H%M%S)"
RUNNING="$LOG_DIR/mm_${START}_running.log"

finish () {
	local end final
	end="$(date +%Y-%m-%d_%H%M%S)"
	final="$LOG_DIR/mm_${START}__${end}.log"

	if [[ -f "$RUNNING" ]]; then
		mv "$RUNNING" "$final"
		echo
		echo "Log saved: $final"
		echo "Runtime:   $START to $end"

		# Prune old logs so the directory does not fill up.
		if (( KEEP_LOGS > 0 )); then
			local count
			count=$(find "$LOG_DIR" -maxdepth 1 -name 'mm_*.log' | wc -l)
			if (( count > KEEP_LOGS )); then
				find "$LOG_DIR" -maxdepth 1 -name 'mm_*.log' -printf '%T@ %p\n' \
					| sort -n \
					| head -n $(( count - KEEP_LOGS )) \
					| cut -d' ' -f2- \
					| xargs -r rm --
				echo "Pruned old logs, keeping $KEEP_LOGS."
			fi
		fi
	fi
}
trap finish EXIT

echo "Logging to: $RUNNING"
echo

cd "$MM_ROOT"
node --run server 2>&1 | tee "$RUNNING"