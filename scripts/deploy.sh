#!/usr/bin/env bash
#
# deploy.sh -- pull-based deployment for the mirror (ADR-009)
#
# Runs on the Pi from a systemd user timer. GitHub cannot reach the Pi
# (behind the router), so the Pi asks instead:
#
#   1. Is there a new commit on origin/main?
#   2. Did CI pass for exactly that commit?        (GitHub API, no token)
#   3. Fast-forward, restart only what changed.
#   4. Smoke test. On failure: back to the previous commit.
#
# Usage:
#   scripts/deploy.sh                 normal run (what the timer does)
#   scripts/deploy.sh --dry-run       check and report, change nothing
#   scripts/deploy.sh --plan OLD NEW  show which services a range would restart
#
# Logs go to the journal:  journalctl --user -u deploy -n 50
#
# What it never touches: config/secrets.js, guest-wifi.png and anything else
# that is git-ignored. Installed systemd units are not overwritten -- a change
# under systemd/ is reported and has to be installed by hand, as is a change
# to the OS update config under config/os/.
#
# A change to modules.txt or bootstrap.sh runs bootstrap.sh, which moves the
# third-party modules to their new pins (docs/updates.md). A rollback runs it
# again with the old modules.txt and so restores the old pins.
set -euo pipefail

# Run from a private copy: a deployment may update this very file, and bash
# reads a script while it executes it -- changing it underneath is undefined.
if [[ -z "${DEPLOY_REPO_ROOT:-}" ]]; then
	DEPLOY_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	export DEPLOY_REPO_ROOT
	self="$(mktemp "${TMPDIR:-/tmp}/mirror-deploy.XXXXXX")"
	cp "${BASH_SOURCE[0]}" "$self"
	exec bash "$self" "$@"
fi
trap 'rm -f "${BASH_SOURCE[0]}"' EXIT

REPO_ROOT="$DEPLOY_REPO_ROOT"
BRANCH="${DEPLOY_BRANCH:-main}"
GITHUB_REPO="${DEPLOY_GITHUB_REPO:-bikenthusiast/raspberrypi-magicmirror}"
MM_URL="${DEPLOY_MM_URL:-http://localhost:8080}"
SMOKE_TIMEOUT="${DEPLOY_SMOKE_TIMEOUT:-120}"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/mirror-deploy.lock"
# A commit that failed the smoke test is remembered here and not retried;
# the next commit on main is tried normally. Delete the file to force a retry.
FAILED_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/mirror-deploy/failed-commit"

log () { echo "deploy: $*"; }
die () { echo "deploy: ERROR: $*" >&2; exit 1; }

# --- what a change means ------------------------------------------------------
#
# One line per changed path: "bootstrap modules", "restart <unit>",
# "user-restart <unit>" or "manual <reason>". The sorted plan runs
# "bootstrap" before any restart. Kept as a single function so the mapping is in one place
# and can be checked with --plan before it ever runs for real.
actions_for () {
	local path="$1"
	case "$path" in
		modules/*|config/config.js|config/custom.css)
			echo "user-restart magicmirror" ;;
		scripts/presence.py)
			echo "restart presence" ;;
		scripts/edge_bridge.py)
			echo "restart edge-bridge" ;;
		systemd/*)
			echo "manual unit changed: $path -- install it by hand (see the header of the file)" ;;
		modules.txt|scripts/bootstrap.sh)
			echo "bootstrap modules"
			echo "user-restart magicmirror" ;;
		config/os/*|scripts/setup-os-updates.sh)
			echo "manual OS update config changed -- run: sudo scripts/setup-os-updates.sh" ;;
		config/*.example|config/*.example.js)
			echo "manual template changed: $path -- compare with your local copy" ;;
		*)
			;;  # docs, tests, scripts called on demand (guest-page.sh): nothing to do
	esac
}

plan () {
	local old="$1" new="$2"
	git -C "$REPO_ROOT" diff --name-only "$old" "$new" \
		| while IFS= read -r p; do actions_for "$p"; done \
		| sort -u
}

# --- CI gate ------------------------------------------------------------------
#
# All check runs for the commit must be finished and successful (or skipped).
# No check runs at all counts as "not green": a commit that never ran CI is
# not deployed.
ci_green () {
	local sha="$1" json
	json="$(curl -fsS --max-time 20 \
		-H "Accept: application/vnd.github+json" \
		"https://api.github.com/repos/$GITHUB_REPO/commits/$sha/check-runs?per_page=100")" \
		|| { log "GitHub API not reachable -- try again next run"; return 1; }
	python3 -c '
import json, sys
runs = json.load(sys.stdin).get("check_runs", [])
if not runs:
    print("no check runs"); sys.exit(1)
bad = ["%s=%s/%s" % (r["name"], r["status"], r["conclusion"]) for r in runs
       if r["status"] != "completed" or r["conclusion"] not in ("success", "skipped", "neutral")]
if bad:
    print("not green: " + ", ".join(bad)); sys.exit(1)
print(f"{len(runs)} checks green")
' <<<"$json"
}

# --- restart and smoke test ---------------------------------------------------

# Returns non-zero when bootstrap.sh fails: the modules may be half updated,
# so the remaining actions are skipped and the caller rolls back. Restart failures are only
# logged here -- the smoke test catches a service that did not come up.
apply_actions () {
	local line
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		case "$line" in
			"bootstrap "*)    log "bootstrap.sh: modules to the pins in modules.txt"
			                  if BOOTSTRAP_NO_HINTS=1 "$REPO_ROOT/scripts/bootstrap.sh" 2>&1 \
			                      | sed -e 's/\x1b\[[0-9;]*m//g' -e '/^[[:space:]]*$/d' -e 's/^/deploy:   /'; then
			                      :
			                  else
			                      log "bootstrap.sh failed"; return 1
			                  fi ;;
			"user-restart "*) log "restart (user) ${line#user-restart }"
			                  systemctl --user restart "${line#user-restart }" \
			                      || log "restart of ${line#user-restart } failed" ;;
			"restart "*)      log "restart ${line#restart }"
			                  # needs the sudoers rule from docs/cicd/README.md
			                  sudo -n systemctl restart "${line#restart }" \
			                      || log "restart of ${line#restart } failed" ;;
			"manual "*)       log "MANUAL STEP: ${line#manual }" ;;
		esac
	done <<<"$1"
}

smoke_test () {
	local actions="$1" unit t=0
	if grep -q "magicmirror" <<<"$actions"; then
		until curl -fsS --max-time 5 -o /dev/null "$MM_URL"; do
			(( t += 5 ))
			(( t >= SMOKE_TIMEOUT )) && { log "MagicMirror not answering on $MM_URL"; return 1; }
			sleep 5
		done
		systemctl --user is-active --quiet magicmirror || { log "magicmirror not active"; return 1; }
	fi
	while IFS= read -r unit; do
		[[ -z "$unit" ]] && continue
		sleep 3
		systemctl is-active --quiet "$unit" || { log "$unit not active"; return 1; }
	done < <(sed -n 's/^restart //p' <<<"$actions")
	return 0
}

# --- main ---------------------------------------------------------------------

main () {
	local dry=0
	case "${1:-}" in
		--plan)    [[ $# -eq 3 ]] || die "usage: $0 --plan OLD NEW"
		           plan "$2" "$3"; exit 0 ;;
		--dry-run) dry=1 ;;
		"")        ;;
		*)         die "unknown option: $1" ;;
	esac

	exec 9>"$LOCK"
	flock -n 9 || { log "another deploy is running"; exit 0; }

	cd "$REPO_ROOT"

	local current
	current="$(git rev-parse --abbrev-ref HEAD)"
	[[ "$current" == "$BRANCH" ]] || { log "checked out branch is $current, not $BRANCH -- skipping"; exit 0; }

	# The Pi is a deploy target. Local edits to tracked files would be lost
	# by a rollback, so they stop the deployment instead.
	if ! git diff --quiet || ! git diff --cached --quiet; then
		log "local changes to tracked files -- skipping (commit them on the Mac, or: git stash)"
		git status --short --untracked-files=no
		exit 0
	fi

	git fetch --quiet origin "$BRANCH"
	local old new
	old="$(git rev-parse HEAD)"
	new="$(git rev-parse "origin/$BRANCH")"

	if [[ "$old" == "$new" ]]; then
		log "up to date at ${old:0:7}"
		exit 0
	fi
	git merge-base --is-ancestor "$old" "$new" \
		|| { log "origin/$BRANCH is not a fast-forward of ${old:0:7} -- skipping"; exit 0; }

	if [[ -f "$FAILED_FILE" && "$(cat "$FAILED_FILE")" == "$new" ]]; then
		log "${new:0:7} failed to deploy before -- waiting for a newer commit (rm $FAILED_FILE to retry)"
		exit 0
	fi

	local gate
	gate="$(ci_green "$new")" || { log "${new:0:7}: $gate -- waiting"; exit 0; }
	log "${new:0:7}: $gate"

	local actions line
	actions="$(plan "$old" "$new")"
	log "update ${old:0:7} -> ${new:0:7}"
	git log --oneline "$old..$new" | sed 's/^/deploy:   /'
	if [[ -n "$actions" ]]; then
		while IFS= read -r line; do log "plan: $line"; done <<<"$actions"
	fi

	if (( dry )); then
		log "dry run -- nothing changed"
		exit 0
	fi

	git merge --ff-only --quiet "$new"
	local since
	since="$(date '+%Y-%m-%d %H:%M:%S')"

	if apply_actions "$actions" && smoke_test "$actions"; then
		log "deployed ${new:0:7}"
		rm -f "$FAILED_FILE"
		# The smoke test sees MagicMirror answer, not whether every module works.
		# After a module update, point at errors a human should look at.
		if grep -q "^bootstrap " <<<"$actions"; then
			local errs
			errs="$(journalctl -t magicmirror --since "$since" --no-pager 2>/dev/null | grep -c "ERROR" || true)"
			if (( errs > 0 )); then
				log "modules updated; MagicMirror logged $errs ERROR line(s) since -- journalctl -t magicmirror --since '$since'"
			else
				log "modules updated; no ERROR lines from MagicMirror so far"
			fi
		fi
		return 0
	fi

	log "bootstrap or smoke test failed -- rolling back to ${old:0:7}"
	mkdir -p "$(dirname "$FAILED_FILE")"
	echo "$new" > "$FAILED_FILE"
	git reset --hard --quiet "$old"
	# Runs bootstrap.sh again if it ran before: modules.txt is the old one now,
	# so this puts the modules back on their old pins.
	apply_actions "$(grep -v '^manual ' <<<"$actions" || true)" || log "bootstrap.sh failed during rollback"
	if smoke_test "$actions"; then
		log "rolled back to ${old:0:7}; ${new:0:7} needs a look"
	else
		log "rollback did not recover the services -- check: journalctl -t magicmirror -b"
	fi
	exit 1
}

main "$@"
