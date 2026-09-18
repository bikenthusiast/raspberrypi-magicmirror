#!/usr/bin/env bash
#
# bootstrap.sh -- installs every module listed in modules.txt
#
# Idempotent: modules already present are updated, not re-cloned.
#
# Usage:  ./scripts/bootstrap.sh [/path/to/MagicMirror]
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MM_ROOT="${1:-$HOME/Projects/MagicMirror}"
MODULES_DIR="$MM_ROOT/modules"
MANIFEST="$REPO_ROOT/modules.txt"

RED=$'\033[0;31m'; YELLOW=$'\033[0;33m'; GREEN=$'\033[0;32m'; NC=$'\033[0m'

[[ -d "$MM_ROOT" ]] || {
	echo "${RED}ERROR${NC} MagicMirror not found at $MM_ROOT" >&2
	echo "      Pass the path as an argument, or install MagicMirror first." >&2
	exit 1
}

[[ -f "$MANIFEST" ]] || {
	echo "${RED}ERROR${NC} $MANIFEST not found" >&2
	exit 1
}

mkdir -p "$MODULES_DIR"

# Log directory for scripts/run-server.sh (manual runs in server mode).
# The systemd service itself logs to the journal.
mkdir -p "$MM_ROOT/logs"

# --- 1. Clone or update the third-party modules ----------------------

while read -r name url pin; do
	[[ -z "${name:-}" || "$name" == \#* ]] && continue

	target="$MODULES_DIR/$name"

	if [[ -d "$target/.git" ]]; then
		echo "==> $name: updating"
		git -C "$target" fetch --quiet origin
	else
		echo "==> $name: cloning"
		git clone --quiet "$url" "$target"
	fi

	if [[ -n "${pin:-}" ]]; then
		git -C "$target" checkout --quiet "$pin"
		echo "    pinned to $pin"
	else
		branch="$(git -C "$target" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||' || echo master)"
		git -C "$target" checkout --quiet "$branch"
		git -C "$target" pull --quiet --ff-only origin "$branch" || true
		echo "    ${YELLOW}no pin${NC}, tracking $branch"
	fi

	# npm install only where dependencies are declared
	if [[ -f "$target/package.json" ]] && grep -q '"dependencies"' "$target/package.json"; then
		echo "    npm install"
		(cd "$target" && npm install --omit=dev --silent)
	fi
done < "$MANIFEST"

# --- 2. Patch the two Fabrizz modules --------------------------------
#
# Both bundle node-fetch 2.7.0, which fails to decompress gzip response
# bodies on Node 18+. The symptom is ERR_STREAM_PREMATURE_CLOSE thrown
# at Gunzip, retried at the poll interval with no backoff -- only a
# restart clears it.
#
# Native fetch has been available since Node 18, so the polyfill is
# only needed on older installs. The ?? keeps that fallback intact.
#
# Reported upstream: github.com/Fabrizz/MMM-OnSpotify/issues/116
# Once fixed there, this section can go.

patch_fetch () {
	local file="$1" label="$2"

	[[ -f "$file" ]] || {
		echo "    ${YELLOW}skipped${NC} $label: $file not found"
		return
	}

	if grep -q 'globalThis.fetch ?? require' "$file"; then
		echo "    $label: already patched"
		return
	fi

	if ! grep -q '^const fetch = require("node-fetch");' "$file"; then
		echo "    ${YELLOW}skipped${NC} $label: import line not found, check manually"
		return
	fi

	cp "$file" "$file.orig"
	sed -i 's|^const fetch = require("node-fetch");|const fetch = globalThis.fetch ?? require("node-fetch");|' "$file"
	sed -i 's|^const Headers = fetch.Headers;|const Headers = globalThis.Headers ?? fetch.Headers;|' "$file"
	echo "    ${GREEN}patched${NC} $label (backup at $(basename "$file").orig)"
}

echo
echo "==> node-fetch patches"
patch_fetch "$MODULES_DIR/MMM-OnSpotify/utils/SpotifyFetcher.js" "MMM-OnSpotify"
patch_fetch "$MODULES_DIR/MMM-LiveLyrics/utils/LyricsFetcher.js" "MMM-LiveLyrics"

# A half-applied patch leaves `const Headers;` without an initializer,
# which surfaces as "Missing initializer in const declaration" in the
# MagicMirror log -- naming neither file nor line.
echo
echo "==> verifying patched files"
for f in \
	"$MODULES_DIR/MMM-OnSpotify/utils/SpotifyFetcher.js" \
	"$MODULES_DIR/MMM-LiveLyrics/utils/LyricsFetcher.js"
do
	[[ -f "$f" ]] || continue
	if node --check "$f" 2>/dev/null; then
		echo "    ${GREEN}ok${NC} $(basename "$f")"
	else
		echo "    ${RED}SYNTAX ERROR${NC} $f"
		node --check "$f" 2>&1 | head -3 | sed 's/^/      /'
	fi
done

# --- 3. Symlink the modules kept in this repo ------------------------
#
# ln -sfn, not ln -s: if the target exists as a directory, ln -s places
# the link inside it and everything ends up one level too deep.

echo
echo "==> own modules"
for own in MMM-SpotifyPages MMM-GuestWifi; do
	src="$REPO_ROOT/modules/$own"
	if [[ -d "$src" ]]; then
		ln -sfn "$src" "$MODULES_DIR/$own"
		echo "    linked $own"
	else
		echo "    ${YELLOW}missing${NC} $own at $src"
	fi
done

# --- 4. Summary ------------------------------------------------------

echo
echo "${GREEN}Done.${NC} Next:"
echo "  1. Credentials:"
echo "     cp $REPO_ROOT/config/secrets.example.js $REPO_ROOT/config/secrets.js"
echo "     chmod 600 $REPO_ROOT/config/secrets.js"
echo "     nano $REPO_ROOT/config/secrets.js"
echo
echo "  2. Link the config:"
echo "     ln -sfn $REPO_ROOT/config/config.js $MM_ROOT/config/config.js"
echo
echo "  3. Generate the guest WiFi code:"
echo "     $REPO_ROOT/scripts/make-guest-qr.sh"
echo
echo "  4. Check it loads:"
echo "     node -e \"require('$MM_ROOT/config/config.js')\""
