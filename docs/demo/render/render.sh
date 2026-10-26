#!/usr/bin/env bash
#
# render.sh -- renders the README screenshots and the demo GIF
#
# Usage:  docs/demo/render/render.sh [work dir]     (default: ${TMPDIR:-/tmp}/mirror-demo)
#
# Runs on the development machine, not on the Pi. It builds a throwaway
# MagicMirror in the work dir from this repository alone:
#
#   1. MagicMirror at MM_VERSION, server-only dependencies
#   2. scripts/bootstrap.sh against it: pinned modules, patches, own modules,
#      the stylesheet link -- the same steps as on the Pi
#   3. a config built from config/config.js by demo-config.js, with
#      mock-backend.js in place of the secrets (weather, calendars, news)
#   4. capture.js in headless Chrome: one screenshot per page, then the tour
#   5. ffmpeg turns the tour into docs/demo/gif/demo_magicmirror.gif
#
# MVG departures and the rain radar are live; everything else is demo data,
# so nothing private ends up in a picture. A second run reuses the work dir.
#
# Needs: git, curl, node + npm, ffmpeg, Chrome or Chromium (CHROME=... to point
# at it), GNU sed -- bootstrap.sh patches with sed -i (macOS: brew install gnu-sed).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
WORK="${1:-${TMPDIR:-/tmp}/mirror-demo}"
WORK="${WORK%/}"
MM_VERSION="${MM_VERSION:-v2.37.0}"
MM_PORT="${DEMO_PORT:-8090}"
MOCK_PORT="${DEMO_MOCK_PORT:-8099}"
MM="$WORK/MagicMirror"
TOOLS="$WORK/tools"
SHOTS="$REPO_ROOT/docs/demo/screenshots"
GIF="$REPO_ROOT/docs/demo/gif/demo_magicmirror.gif"

log () { echo "==> $*"; }
die () { echo "render: ERROR: $*" >&2; exit 1; }

for cmd in git curl node npm ffmpeg; do
	command -v "$cmd" >/dev/null || die "$cmd not found"
done
for port in "$MM_PORT" "$MOCK_PORT"; do
	! curl -s -m 2 -o /dev/null "http://localhost:$port" || die "port $port is in use (DEMO_PORT / DEMO_MOCK_PORT)"
done
mkdir -p "$WORK"

# bootstrap.sh uses GNU sed -i; on macOS put gsed first in PATH as "sed"
if ! sed --version >/dev/null 2>&1; then
	command -v gsed >/dev/null || die "GNU sed needed for bootstrap.sh (macOS: brew install gnu-sed)"
	mkdir -p "$WORK/bin"
	ln -sf "$(command -v gsed)" "$WORK/bin/sed"
	PATH="$WORK/bin:$PATH"
fi

# --- 1. MagicMirror ----------------------------------------------------

if [[ ! -d "$MM/.git" ]]; then
	log "MagicMirror $MM_VERSION"
	git clone --quiet --depth 1 --branch "$MM_VERSION" https://github.com/MagicMirrorOrg/MagicMirror.git "$MM"
fi
if [[ ! -d "$MM/node_modules" ]]; then
	log "MagicMirror dependencies (server only)"
	# engine-strict off: the dev machine's Node may trail MagicMirror's range
	(cd "$MM" && npm ci --omit=dev --omit=optional --ignore-scripts --engine-strict=false --no-audit --no-fund --silent)
fi

# --- 2. Modules, the same way as on the Pi ------------------------------

# The guest page gets a demo code, not the real password: MMM-GuestWifi is
# copied instead of linked, so guest-wifi.png stays in the work dir. The code
# holds this repository's URL -- no Wi-Fi string, real or made up, to leak or
# to trip the pre-commit hook. A copy from an earlier run goes first: ln -sfn
# would link inside a directory.
guest="$MM/modules/MMM-GuestWifi"
if [[ -d "$guest" && ! -L "$guest" ]]; then
	rm -r -- "$guest"
fi

log "modules (scripts/bootstrap.sh)"
BOOTSTRAP_NO_HINTS=1 "$REPO_ROOT/scripts/bootstrap.sh" "$MM" | sed 's/^/    /'

rm -- "$guest"
cp -R "$REPO_ROOT/modules/MMM-GuestWifi" "$guest"

if [[ ! -d "$TOOLS/node_modules/puppeteer-core" ]]; then
	log "capture tools (puppeteer-core, qrcode)"
	mkdir -p "$TOOLS"
	(cd "$TOOLS" && npm init -y >/dev/null && npm install --no-audit --no-fund --silent puppeteer-core@23 qrcode@1)
fi
node -e 'require(require.resolve("qrcode", { paths: [process.argv[1]] })).toFile(process.argv[2], process.argv[3], { margin: 2, width: 600 })' \
	"$TOOLS" "$guest/guest-wifi.png" "https://github.com/bikenthusiast/raspberrypi-magicmirror"

# --- 3. Demo config ----------------------------------------------------

node "$HERE/demo-config.js" "$REPO_ROOT/config/config.js" "$MM/config/config.js" "http://localhost:$MOCK_PORT" "$MM_PORT"
printf '%s\n' \
	'@import url("https://fonts.googleapis.com/css2?family=Inter:opsz,wght@14..32,100..900&display=block");' \
	'@import url("custom.css");' > "$MM/config/demo.css"

# --- 4. Servers and capture --------------------------------------------

mock_pid=""
mm_pid=""
cleanup () {
	[[ -n "$mm_pid" ]] && kill "$mm_pid" 2>/dev/null
	[[ -n "$mock_pid" ]] && kill "$mock_pid" 2>/dev/null
	return 0
}
trap cleanup EXIT

MOCK_RAIN=1 node "$HERE/mock-backend.js" "$MOCK_PORT" > "$WORK/mock.log" 2>&1 &
mock_pid=$!
(cd "$MM" && exec node ./serveronly) > "$WORK/magicmirror.log" 2>&1 &
mm_pid=$!

log "waiting for MagicMirror on port $MM_PORT"
for _ in $(seq 60); do
	curl -fs -o /dev/null "http://localhost:$MM_PORT" && break
	sleep 1
done
curl -fs -o /dev/null "http://localhost:$MM_PORT" || die "MagicMirror did not start -- see $WORK/magicmirror.log"

log "capture"
mkdir -p "$SHOTS"
DEMO_TOOLS="$TOOLS" node "$HERE/capture.js" "http://localhost:$MM_PORT" "$SHOTS" "$WORK/tour.webm" "http://localhost:$MOCK_PORT"

# --- 5. GIF ------------------------------------------------------------

log "GIF"
mkdir -p "$(dirname "$GIF")"
ffmpeg -loglevel error -y -i "$WORK/tour.webm" \
	-vf "fps=10,scale=450:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
	-loop 0 "$GIF"

log "done"
ls -l "$SHOTS"/page*.png "$GIF" | awk '{printf "    %8.0f KB  %s\n", $5 / 1024, $NF}'
