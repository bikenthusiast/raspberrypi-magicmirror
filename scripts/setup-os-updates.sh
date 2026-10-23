#!/usr/bin/env bash
#
# setup-os-updates.sh -- automatic security updates for the mirror Pi
#
# Installs unattended-upgrades, restricted to Debian security updates, and
# moves the apt timers into the Witty Pi window. Idempotent: run it again
# after config/os/ changed (deploy.sh reports that as a manual step).
#
#   config/os/52unattended-upgrades-mirror  -> /etc/apt/apt.conf.d/
#   config/os/apt-daily.timer.conf          -> /etc/systemd/system/apt-daily.timer.d/mirror.conf
#   config/os/apt-daily-upgrade.timer.conf  -> /etc/systemd/system/apt-daily-upgrade.timer.d/mirror.conf
#
# Usage:
#   sudo scripts/setup-os-updates.sh           install / update
#   scripts/setup-os-updates.sh --check        show what is installed and what would run
#
# Background: docs/updates.md, ADR-011.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/config/os"

declare -A TARGETS=(
	["52unattended-upgrades-mirror"]="/etc/apt/apt.conf.d/52unattended-upgrades-mirror"
	["apt-daily.timer.conf"]="/etc/systemd/system/apt-daily.timer.d/mirror.conf"
	["apt-daily-upgrade.timer.conf"]="/etc/systemd/system/apt-daily-upgrade.timer.d/mirror.conf"
)

check () {
	local ok=1 f
	echo "==> files"
	for f in "${!TARGETS[@]}"; do
		if cmp -s "$SRC/$f" "${TARGETS[$f]}"; then
			echo "    ok       ${TARGETS[$f]}"
		elif [[ -f "${TARGETS[$f]}" ]]; then
			echo "    DIFFERS  ${TARGETS[$f]} (run: sudo $0)"; ok=0
		else
			echo "    MISSING  ${TARGETS[$f]} (run: sudo $0)"; ok=0
		fi
	done

	echo "==> unattended-upgrades"
	if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
		echo "    installed"
	else
		echo "    NOT INSTALLED"; ok=0
	fi
	echo "    origins: $(apt-config dump 2>/dev/null | sed -n 's/^Unattended-Upgrade::Origins-Pattern:: "\(.*\)";/\1/p' | paste -sd ' ')"
	echo "    periodic: $(apt-config dump 2>/dev/null | grep -E '^APT::Periodic::(Update-Package-Lists|Unattended-Upgrade) ' | tr -d '";' | paste -sd ' ')"

	echo "==> timers"
	systemctl list-timers --all --no-pager apt-daily.timer apt-daily-upgrade.timer 2>/dev/null | head -4 | sed 's/^/    /'

	echo "==> last runs"
	journalctl -t unattended-upgrade -n 3 --no-pager -q 2>/dev/null | sed 's/^/    /' || true
	(( ok )) && echo "all in place" || { echo "incomplete"; return 1; }
}

if [[ "${1:-}" == "--check" ]]; then
	check
	exit $?
fi
[[ $# -eq 0 ]] || { echo "Usage: sudo $0 | $0 --check" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "run with sudo (or use --check)" >&2; exit 1; }

echo "==> unattended-upgrades"
if ! dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
	apt-get install -y -q unattended-upgrades
fi

echo "==> config"
for f in "${!TARGETS[@]}"; do
	install -D -m 0644 "$SRC/$f" "${TARGETS[$f]}"
	echo "    ${TARGETS[$f]}"
done

systemctl daemon-reload
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null
systemctl restart apt-daily.timer apt-daily-upgrade.timer

# Syntax check of the apt configuration: apt-config fails on a broken file.
apt-config dump >/dev/null

echo
check
echo
echo "Test run without installing anything:"
echo "  sudo unattended-upgrade --dry-run --debug 2>&1 | grep -iE 'allowed origins|packages that will be upgraded'"
